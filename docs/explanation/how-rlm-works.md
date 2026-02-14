# How RLM Works

This document explains the architecture and concepts behind Recursive Language Models.

## The Context Rot Problem

Traditional LLM calls suffer from "context rot" - performance degrades as context length increases. When you dump a large document into a prompt, the model struggles to:

- Find specific information buried in thousands of tokens
- Maintain coherent reasoning across long contexts
- Avoid hallucinating when information is sparse

## The RLM Solution

Instead of processing all context at once, RLMs give the LLM a **REPL environment** where it can:

1. Write code to analyze context programmatically
2. Spawn recursive sub-queries to specialized models
3. Accumulate results across multiple iterations
4. Signal when it has found the final answer

The key insight is that **Lua execution is instant** while LLM calls are expensive. By letting the model write code, it can efficiently navigate large contexts without consuming its entire token budget upfront.

## Architecture Overview

```
User Query + Context
        |
        v
+------------------+
|   REPL Loop      |  (max 10 iterations - configurable)
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
  Append output to history
  Continue iteration
```

## Two-Stage Prompting

The LLM receives different prompts depending on the iteration:

### Exploration Phase (iterations 2+)

During exploration, the prompt encourages the model to:
- Use Lua operations to inspect the context
- Break down large contexts into chunks
- Use `rlm.llm_query()` for recursive analysis
- Build up intermediate results

### Final Answer Phase (last iteration)

On the final iteration, the prompt instructs the model to:
- Synthesize all findings from the REPL history
- Return a definitive answer using `return`
- Not attempt new analysis

This two-stage approach prevents the model from prematurely answering before gathering enough information.

## The Iteration Loop

Each iteration:

1. **Build prompt** - Include query, REPL history, remaining iterations
2. **Call LLM** - Generate Lua code
3. **Execute code** - Run in sandboxed Luerl environment
4. **Check result**:
   - If `return` was called → end with final answer
   - If code printed output → append to history, continue
   - If error occurred → append error to history, continue

The history grows with each iteration, giving the LLM visibility into its previous attempts.

## Error Recovery

Lua runtime and compiler errors are captured and shown to the LLM in subsequent iterations. This is intentional - it allows the model to:

- See what went wrong
- Adjust its approach
- Self-correct without crashing the session

This is especially useful for handling Luerl's limitations (like missing `string.gmatch`).

## Recursive Sub-Queries

The `rlm.llm_query(query, context)` function spawns a nested RLM completion:

```lua
-- Analyze each chunk with a sub-query
for i, chunk in ipairs(chunks) do
  local summary, err = rlm.llm_query("Summarize this section", chunk)
  if summary then
    table.insert(summaries, summary)
  end
end
```

Sub-queries have their own iteration budgets and can themselves spawn sub-queries (up to `max_depth`).

## Chunking Strategies

When analyzing large contexts, efficient chunking is critical since each `rlm.llm_query()` call consumes iteration budget.

### Guidelines

- **Target 10-50 chunks maximum** per analysis
- **500K-10M contexts**: ~20 chunks of ~500K each
- **10M+ contexts**: Use hierarchical summarization (summarize groups, then summarize summaries)

### Chunk Size Formula

```lua
local chunk_size = math.ceil(#context / 20)
```

### Pattern-Based Splitting

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

## Why Lua?

Lua was chosen for several reasons:

1. **Simple syntax** - Easy for LLMs to generate correctly
2. **Fast execution** - Luerl runs natively in Erlang/BEAM
3. **Sandboxable** - Easy to restrict dangerous operations
4. **Minimal** - Small stdlib means less for the LLM to hallucinate

The trade-off is that Luerl has a restricted standard library compared to native Lua (see `ExRLM.LuaRepl` for details).

## Module Architecture

| Module | Responsibility |
|--------|----------------|
| `ExRLM` | Public API facade, iteration loop |
| `ExRLM.LLM` | Type definitions (Message, Response, Usage) |
| `ExRLM.LuaRepl` | Lua sandbox, execution, error capture |
| `ExRLM.Lua.Completion` | Implements `rlm.llm_query()` callback |
| `ExRLM.Completion.OpenAI` | OpenAI API implementation |

Prompts are defined as EEx templates in `priv/templates/`.

## References

- [Recursive Language Models (RLMs) - Alex Zhang](https://alexzhang13.github.io/blog/2025/rlm/)
- [Luerl - Erlang Lua implementation](https://github.com/rvirding/luerl)
