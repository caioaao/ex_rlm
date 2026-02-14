# Getting Started with ExRLM

This tutorial walks you through your first RLM completion, from setup to understanding the output.

## Prerequisites

- Elixir 1.19+
- An OpenAI API key (or another LLM provider)

## Installation

Add ExRLM to your `mix.exs`:

```elixir
def deps do
  [
    {:ex_rlm, "~> 0.1.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

Set your OpenAI API key:

```bash
export OPENAI_API_KEY="sk-..."
```

## Your First Completion

Let's create a simple script that uses ExRLM to analyze a document.

### Step 1: Create the RLM Instance

```elixir
# Create an RLM with OpenAI's GPT-4o model
rlm = ExRLM.new(%{llm: ExRLM.Completion.OpenAI.new("gpt-4o")})
```

### Step 2: Run a Completion

```elixir
context = """
The quick brown fox jumps over the lazy dog. This sentence contains every
letter of the alphabet and is commonly used for typing practice and font
demonstrations. It was popularized in the early 20th century.
"""

{:ok, answer} = ExRLM.completion(
  rlm,
  "What is this text commonly used for?",
  context: context
)

IO.puts(answer)
# => "This text is commonly used for typing practice and font demonstrations."
```

## Understanding the Output

When you run a completion, the LLM:

1. Receives your query and context
2. Generates Lua code to analyze the context
3. Executes the code in a sandboxed environment
4. Either returns a final answer or continues iterating

You can see the iteration process by checking your logs (the library uses `Logger.info`).

## Adjusting Limits

For larger contexts, you may need more iterations:

```elixir
{:ok, answer} = ExRLM.completion(
  rlm,
  "Summarize all key points",
  context: very_large_document,
  max_iterations: 20,  # More iterations for complex analysis
  max_depth: 5         # Allow recursive sub-queries
)
```

## Handling Errors

```elixir
case ExRLM.completion(rlm, "Analyze this", context: ctx) do
  {:ok, answer} ->
    IO.puts("Answer: #{answer}")

  {:error, :max_iterations_reached} ->
    IO.puts("The LLM couldn't find an answer within the iteration limit")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Next Steps

- Read the [How RLM Works](how-rlm-works.md) guide to understand the architecture
- Learn how to [create custom LLM providers](custom-llm-providers.md)
- Try the needle-in-haystack example: `mix run examples/needle_in_haystack.exs`
