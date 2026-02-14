# ExRLM

An Elixir implementation of [Recursive Language Models (RLMs)](https://alexzhang13.github.io/blog/2025/rlm/) - enabling LLMs to reason through complex problems iteratively via a Lua REPL.

## The Idea

Traditional LLM calls suffer from "context rot" - performance degrades as context length increases. RLMs solve this by giving the model a **REPL environment** where it can:

- Write code to analyze context programmatically
- Spawn recursive sub-queries to specialized models
- Accumulate results across multiple iterations
- Signal when it has found the final answer

Instead of dumping all context into a prompt, the LLM writes Lua code that interacts with the data strategically.

## When to Use ExRLM

**Good fit:**
- Large contexts (100K+ characters) that overwhelm single prompts
- Questions requiring systematic analysis (finding needles, summarizing sections)
- Tasks where the LLM needs to "think step by step" programmatically

**Not a good fit:**
- Simple prompts with small contexts (overhead not worth it)
- Real-time latency requirements under 5 seconds (multiple LLM calls take time)
- Non-Elixir applications (use the [original Python RLM](https://alexzhang13.github.io/blog/2025/rlm/))

## Quickstart

```bash
export OPENAI_API_KEY="sk-..."
```

```elixir
# Create an RLM instance
rlm = ExRLM.new(%{llm: ExRLM.Completion.OpenAI.new("gpt-4o")})

# Run a completion
{:ok, answer} = ExRLM.completion(
  rlm,
  "What is the main theme of this text?",
  context: "Your long document here..."
)
```

Try the needle-in-haystack example:

```bash
mix run examples/needle_in_haystack.exs
```

## Documentation

- **[Getting Started](doc/tutorials/getting-started.md)** - Step-by-step tutorial
- **[How RLM Works](doc/explanation/how-rlm-works.md)** - Architecture and concepts
- **[Custom LLM Providers](doc/guides/custom-llm-providers.md)** - Implement your own provider
- **[API Reference](https://hexdocs.pm/ex_rlm)** - Module documentation

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [{:ex_rlm, "~> 0.1.0"}]
end
```

## References

- [Recursive Language Models (RLMs) - Alex Zhang](https://alexzhang13.github.io/blog/2025/rlm/)
