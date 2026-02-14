defmodule ExRLM do
  @moduledoc """
  An Elixir implementation of Recursive Language Models (RLMs).

  RLMs enable LLMs to reason through complex problems iteratively via a Lua REPL,
  solving the "context rot" problem where performance degrades as context length increases.

  ## Quick Start

      # Create an RLM with OpenAI
      rlm = ExRLM.new(%{llm: ExRLM.Completion.OpenAI.new("gpt-4o")})

      # Run a completion
      {:ok, answer} = ExRLM.completion(
        rlm,
        "What is the main theme of this text?",
        context: "Your long document here..."
      )

  ## Configuration

  ### `new/1` Options

  | Option | Description |
  |--------|-------------|
  | `:llm` | A function `([Message.t]) -> {:ok, Response.t} | {:error, term}`. Use `ExRLM.Completion.OpenAI.new/1` for OpenAI. |

  ### `completion/3` Options

  | Option | Default | Description |
  |--------|---------|-------------|
  | `:context` | `""` | The context to make available in the Lua environment |
  | `:max_iterations` | 10 | Maximum REPL iterations before returning an error |
  | `:max_depth` | 10 | Maximum recursion depth for `rlm.llm_query()` calls |

  REPL outputs longer than 100,000 characters are truncated to prevent token overflow.

  ## Custom LLM Providers

  You can pass any function that takes messages and returns `{:ok, %Response{}}`:

      alias ExRLM.LLM.{Message, Response, Usage}

      my_llm = fn messages ->
        # messages is a list of %Message{role: "...", content: "..."}
        {:ok, %Response{
          content: "response",
          usage: %Usage{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
        }}
      end

      rlm = ExRLM.new(%{llm: my_llm})

  See `ExRLM.LLM` for the callback contract and `ExRLM.Completion.OpenAI` for a reference implementation.
  """
  require Logger

  alias ExRLM.Completion.Prompts.{ReplCompletion, ReplFinalAnswer}
  alias ExRLM.Repl

  defstruct [:config, history: []]

  @type context() :: list(String.t())

  @type config() :: %{llm: ExRLM.LLM.t()}

  @type t() :: %__MODULE__{config: config()}

  @doc """
  Creates a new RLM instance with the given configuration.

  ## Examples

      iex> rlm = ExRLM.new(%{llm: ExRLM.Completion.OpenAI.new("gpt-4o")})
      %ExRLM{config: %{llm: _}}

  """
  @spec new(config()) :: t()
  def new(config) do
    %__MODULE__{config: config}
  end

  @type completion_opt() ::
          {:max_depth, pos_integer()}
          | {:max_iterations, pos_integer()}
          | {:context, context()}

  @doc """
  Runs an RLM completion for the given query.

  The LLM will iteratively generate and execute Lua code to analyze the context
  until it calls `return` with a final answer or hits the iteration limit.

  ## Options

    * `:context` - The context string available as `context` in Lua (default: `""`)
    * `:max_iterations` - Maximum REPL iterations (default: `10`)
    * `:max_depth` - Maximum recursion depth for `rlm.llm_query()` (default: `10`)

  ## Examples

      {:ok, answer} = ExRLM.completion(
        rlm,
        "Summarize this document",
        context: large_document,
        max_iterations: 15
      )

  ## Error Handling

  Returns `{:error, :max_iterations_reached}` if the LLM doesn't return a final
  answer within the iteration limit.

  Lua runtime errors are captured and shown to the LLM in subsequent iterations,
  allowing it to self-correct rather than crashing the session.
  """
  @spec completion(t(), String.t(), keyword(completion_opt())) ::
          {:ok, String.t()} | {:error, term()}
  def completion(rlm, query, opts \\ []) do
    Logger.info("Query: #{query}")

    context = Keyword.get(opts, :context, "")
    max_depth = Keyword.get(opts, :max_depth, 10)
    max_iterations = Keyword.get(opts, :max_iterations, 10)

    # We start with a new RLM without history
    sub_rlm = new(rlm.config)

    completion_fn =
      if max_depth == 1 do
        fn _, _ ->
          {:error, :max_depth_reached}
        end
      else
        fn query, context ->
          completion(sub_rlm, query,
            context: context,
            max_depth: max_depth - 1,
            max_iterations: max_iterations
          )
        end
      end

    repl = ExRLM.LuaRepl.new(completion_fn, context)
    iterate(rlm, repl, query, context, max_iterations)
  end

  defp iterate(_rlm, _repl, _query, _context, 0) do
    {:error, :max_iterations_reached}
  end

  defp iterate(rlm, repl, query, context, iteration) do
    with {:ok, source_code} <- call_llm(rlm, repl, query, iteration) do
      Logger.info("[Iteration #{iteration}] Script:\n#{source_code}")

      ExRLM.LuaRepl.eval(repl, source_code)
      |> case do
        {:halt, final_answer} ->
          Logger.info("[Iteration #{iteration}] Final answer: #{final_answer}")
          {:ok, final_answer}

        {:cont, repl} ->
          Logger.info("[Iteration #{iteration}] Output:\n#{last_output(repl)}")
          iterate(rlm, repl, query, context, iteration - 1)
      end
    end
  end

  defp last_output(repl) do
    case hd(repl.history) do
      %Repl.Interaction{kind: :output, content: content} -> content
      _ -> ""
    end
  end

  defp call_llm(rlm, repl, query, iteration) do
    repl_history = Repl.History.format(repl.history)

    messages =
      if iteration > 1 do
        ReplCompletion.build_messages(%{
          query: query,
          repl_history: repl_history,
          remaining: iteration
        })
      else
        ReplFinalAnswer.build_messages(%{query: query, repl_history: repl_history})
      end

    case rlm.config.llm.(messages) do
      {:ok, %ExRLM.LLM.Response{content: content}} -> {:ok, content}
      {:error, _} = err -> err
    end
  end
end
