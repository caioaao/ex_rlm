# ExRLM

An Elixir implementation of [Recursive Language Models (RLMs)](https://alexzhang13.github.io/blog/2025/rlm/) - enabling LLMs to reason through complex problems iteratively via a Lua REPL.

## The Idea

Traditional LLM calls suffer from "context rot" - performance degrades as context length increases. RLMs solve this by giving the model a **REPL environment** where it can:

- Write code to analyze context programmatically
- Spawn recursive sub-queries to specialized models
- Accumulate results across multiple iterations
- Signal when it has found the final answer

Instead of dumping all context into a prompt, the LLM writes Lua code that interacts with the data strategically.

## Installation

```bash
# Install tool dependencies (Elixir, Lua, etc.)
mise install

# Install package dependencies
mix deps.get

# Set your OpenAI API key
export OPENAI_API_KEY="sk-..."
```

## Usage

### Basic Example

```elixir
# Create an RLM instance
rlm = ExRLM.new(%{model: "GPT4o"})

# Run a completion
{:ok, answer} = ExRLM.completion(
  rlm,
  "What is the main theme of this text?",
  context: "Your long document here..."
)

IO.puts(answer)
```

### With Custom Limits

```elixir
rlm = ExRLM.new(%{model: "GPT4oMini"})

{:ok, answer} = ExRLM.completion(
  rlm,
  "Summarize the key arguments in this legal document",
  context: large_document,
  max_iterations: 15,
  max_depth: 5
)
```

### Needle in Haystack Example

The classic test for context handling - find a magic number hidden in 1 million lines of random text:

```bash
mix run examples/needle_in_haystack.exs
```

## How It Works

```
User Query + Context
        |
        v
+------------------+
|   REPL Loop      |  (max 10 iterations -  configurable)
+------------------+
        |
        v
+------------------+
|  LLM generates   |
|   Lua code       |
+------------------+
        |
        v
+------------------+
|  Execute in      |
|  Lua sandbox     |
+------------------+
        |
        v
  /----------\
 /  return    \-----> Return final answer
 \  called?   /
  \----------/
        | no
        v
  Append result to context
  Continue iteration
```

### Two-Stage Prompting

The LLM receives different prompts depending on the iteration:

1. **Exploration phase** (iterations 2+): Encourages the model to explore the context using Lua operations before answering
2. **Final answer phase** (last iteration): Instructs the model to synthesize findings and return a final answer

### Error Recovery

Lua runtime and compiler errors are captured and shown to the LLM in the REPL history. This allows the model to see its mistakes and correct them in subsequent iterations, rather than crashing the entire session.

## Lua API Reference

The LLM has access to these functions in the Lua environment:

### `return value`

Returns the final answer and ends the session. Accepts strings, numbers, tables, or nil.

```lua
-- When the LLM is ready to respond
return "The main theme is..."
```

### `rlm.llm_query(query, context)`

Spawns a recursive sub-query to analyze a chunk of context. Returns a tuple `(result, error)`:

```lua
-- Always destructure the result
local result, err = rlm.llm_query("Summarize this section", chunk)

if err then
  print("Error: " .. err)  -- Handle error
elseif result then
  -- Use result
end
```

**Error messages:**
- `"max recursion depth reached"` - Hit the `max_depth` limit
- `"max number of iterations reached"` - Hit the `max_iterations` limit
- `"unexpected error occurred: ..."` - Other errors

### `print(value)`

Output values to see in the next iteration. Useful for debugging and inspecting intermediate results.

```lua
print("Context size: " .. #context)
print("First 100 chars: " .. string.sub(context, 1, 100))
```

### Global Variables

Variables assigned without `local` persist across iterations:

```lua
-- First iteration
results = {}  -- Global, persists

-- Second iteration
table.insert(results, chunk_result)  -- Still accessible
```

## Configuration

### `ExRLM.new(config)`

| Option | Description |
|--------|-------------|
| `:model` | BAML client name (e.g., `"GPT4o"`, `"GPT4oMini"`, `"GPT4Turbo"`) |

### `ExRLM.completion(rlm, query, opts)`

| Option | Default | Description |
|--------|---------|-------------|
| `:context` | `""` | The context to make available in the Lua environment |
| `:max_iterations` | 10 | Maximum REPL iterations |
| `:max_depth` | 10 | Maximum recursion depth for `rlm.llm_query()` calls |

**Note:** REPL outputs longer than 100,000 characters are truncated to prevent token overflow.

## Lua Sandbox

The Lua environment runs on [Luerl](https://github.com/rvirding/luerl) (Erlang Lua implementation) and is sandboxed for security.

### Available Functions

```lua
-- String operations
#context                           -- size in bytes
string.sub(s, start, end)          -- substring (1-indexed, end inclusive)
string.find(s, pattern)            -- returns start_pos, end_pos or nil
string.find(s, pattern, init)      -- search from position
string.match(s, pattern)           -- returns captured text or nil
string.lower(s) / string.upper(s)  -- case conversion
string.rep(s, n)                   -- repeat n times
string.reverse(s)                  -- reverse string
string.len(s)                      -- same as #s
string.gsub(s, pattern, repl)      -- replace (string replacement only!)

-- Math operations
math.min(), math.max()
math.floor(), math.ceil()
math.abs(), math.sqrt()

-- Table operations
table.insert(t, v)
table.concat(t, sep)
#table  -- length

-- Type conversions
tonumber(s), tostring(n)
type(v)
pairs(t), ipairs(t)

-- Time (limited)
os.time(), os.date()
```

### Luerl Limitations

Luerl has a restricted stdlib compared to standard Lua:

- `string.gmatch()` and `string.gfind()` **do not exist** - use `string.find()` in a loop
- `string.gsub()` only works with **string replacements**, not replacement functions
- For pattern-based splitting, use `string.find()` + `string.sub()` in a loop

### Blocked Functions

For security, these are disabled:

- File I/O: `io`, `file`
- System access: `os.execute`, `os.exit`, `os.getenv`, `os.remove`, `os.rename`, `os.tmpname`
- Code loading: `require`, `dofile`, `load`, `loadfile`, `loadstring`, `package`
- Debug/introspection: `debug`, `rawget`, `rawset`, `getmetatable`, `setmetatable`
- Memory: `collectgarbage`
- Coroutines: `coroutine`

## Chunking Strategy

When analyzing large contexts, efficient chunking is critical since each `rlm.llm_query()` call consumes iteration budget.

### Guidelines

- **Target 10-50 chunks maximum** per analysis
- **500K-10M contexts**: ~20 chunks of ~500K each
- **10M+ contexts**: Use hierarchical summarization (summarize groups, then summarize summaries)

### Chunk Size Formula

```lua
local chunk_size = math.ceil(#context / 20)
```

### Pattern-Based Splitting Example

```lua
sections = {}
pos = 1
while pos <= #context do
  sep = string.find(context, "\n\n", pos)
  if not sep then
    table.insert(sections, string.sub(context, pos))
    break
  end
  table.insert(sections, string.sub(context, pos, sep-1))
  pos = sep + 2
end
```

## Architecture

- `ExRLM` - Public API facade
- `ExRLM.LuaRepl` - REPL execution, Lua sandboxing, error recovery
- `ExRLM.Lua.Completion` - Implements `rlm.llm_query()` callback
- `ExRLM.Repl.History` - Manages REPL history with truncation
- `ExRLM.LLM` - BAML-based LLM client with iteration-aware prompting

Prompts are defined in `priv/baml_src/main.baml` using [BAML](https://docs.boundaryml.com/).

## Next Steps

- Implement introspection tools for discovering Lua functions (similar to `h` in IEx)
- Support concurrent `rlm.llm_query()` calls (if Luerl supports concurrency)

## References

- [Recursive Language Models (RLMs) - Alex Zhang](https://alexzhang13.github.io/blog/2025/rlm/)
