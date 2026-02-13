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

# Install Elixir dependencies
mix deps.get

# Set your OpenAI API key
export OPENAI_API_KEY="sk-..."
```

## Usage

### Basic Example

```elixir
# Create an RLM instance
rlm = ExRLM.new(model: "gpt-4o")

# Run a completion
{:ok, {rlm, answer}} = ExRLM.completion(
  rlm,
  "What is the main theme of this text?",
  context: "Your long document here..."
)

IO.puts(answer)
```

### With Recursive Model

Use a cheaper model for sub-queries:

```elixir
rlm = ExRLM.new(
  model: "gpt-4o",
  recursive_model: "gpt-4o-mini",
  max_iterations: 15,
  max_depth: 5
)

{:ok, {rlm, answer}} = ExRLM.completion(
  rlm,
  "Summarize the key arguments in this legal document",
  context: large_document
)
```

## How It Works

```
User Query + Context
        |
        v
+------------------+
|   REPL Loop      |  (max 10 iterations)
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
 /  rlm.answer \-----> Return final answer
 \  called?    /
  \----------/
        | no
        v
  Append result to context
  Continue iteration
```

The LLM has access to two special functions in the Lua environment:

### `rlm.answer(value)`

Signals the final answer. Accepts strings, numbers, tables, or nil.

```lua
-- When the LLM is ready to respond
return rlm.answer("The main theme is...")
```

### `rlm.llm_query(query, context)`

Spawns a recursive sub-query to analyze a chunk of context:

```lua
-- Analyze chunks separately, then synthesize
local chunk1_result = rlm.llm_query("Summarize this section", chunk1)
local chunk2_result = rlm.llm_query("Summarize this section", chunk2)

-- Combine results
return rlm.answer(chunk1_result .. "\n" .. chunk2_result)
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `:model` | (required) | Primary LLM model (e.g., "gpt-4o") |
| `:recursive_model` | same as `:model` | Model for `rlm.llm_query()` calls |
| `:max_iterations` | 10 | Maximum reasoning iterations |
| `:max_depth` | 10 | Maximum recursion depth for sub-queries |

## Lua Sandbox

The Lua environment is sandboxed for security. LLM-generated code can use:

**Available:**
- `math.*` - all math operations
- `string.*` - string manipulation
- `table.*` - table operations
- `type()`, `tostring()`, `tonumber()`, `pairs()`, `ipairs()`
- `os.time()`, `os.date()`

**Blocked:**
- File I/O (`io`, `file`)
- System access (`os.execute`, `os.exit`, `os.getenv`)
- Code loading (`require`, `dofile`, `load`, `loadfile`)
- Debug/introspection (`debug`, `rawget`, `rawset`, `getmetatable`)
- Coroutines

## Architecture

- `ExRLM` - Public API facade
- `ExRLM.Repl` - Main loop orchestration, context management, error recovery
- `ExRLM.Lua` - Lua VM setup and sandboxing
- `ExRLM.Lua.Completion` - Implements `rlm.answer()` and `rlm.llm_query()`
- `ExRLM.LLM` - BAML-based LLM client with iteration-aware prompting

## References

- [Recursive Language Models (RLMs) - Alex Zhang](https://alexzhang13.github.io/blog/2025/rlm/)
