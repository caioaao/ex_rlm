defmodule ExRLM do
  @moduledoc """
  An Elixir implementation of Recursive Language Models (RLMs).

  RLMs enable LLMs to reason through complex problems iteratively via a Lua REPL,
  solving the "context rot" problem where performance degrades as context length increases.

  ## Quick Start

      # Run a completion
      {:ok, answer} = ExRLM.completion(
        "What is the main theme of this text?",
        llm: ExRLM.Completion.OpenAI.new("gpt-4o"),
        context: "Your long document here..."
      )

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

      rlm = ExRLM.completion("Your query here...", llm: my_llm)

  See `ExRLM.LLM` for the callback contract and `ExRLM.Completion.OpenAI` for a reference implementation.
  """
  require Logger

  alias ExRLM.Completion.Prompts.{ReplCompletion, ReplFinalAnswer}
  alias ExRLM.Repl

  @type context() :: list(String.t())

  @type completion_opt() ::
          {:llm, ExRLM.LLM.t()}
          | {:max_depth, pos_integer()}
          | {:max_iterations, pos_integer()}
          | {:context, context()}

  @doc """
  Runs an RLM completion for the given query.

  The LLM will iteratively generate and execute Lua code to analyze the context
  until it calls `return` with a final answer or hits the iteration limit.

  ## Options

    * `:llm` - The LLM used to generate completions
    * `:context` - The context string available as `context` in Lua (default: `""`)
    * `:max_iterations` - Maximum REPL iterations (default: `10`)
    * `:max_depth` - Maximum recursion depth for `rlm.llm_query()` (default: `10`)

  ## Examples

      {:ok, answer} = ExRLM.completion(
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
  @spec completion(String.t(), keyword(completion_opt())) ::
          {:ok, String.t()} | {:error, term()}
  def completion(query, opts \\ []) do
    Logger.info("Query: #{query}")

    llm = Keyword.fetch!(opts, :llm)
    context = Keyword.get(opts, :context, "")
    max_depth = Keyword.get(opts, :max_depth, 10)
    max_iterations = Keyword.get(opts, :max_iterations, 10)

    completion_fn =
      if max_depth == 1 do
        fn _, _ ->
          {:error, :max_depth_reached}
        end
      else
        fn query, context ->
          completion(query,
            llm: llm,
            context: context,
            max_depth: max_depth - 1,
            max_iterations: max_iterations
          )
        end
      end

    repl = ExRLM.LuaRepl.new(completion_fn, context)
    iterate(repl, query, context, llm, max_iterations)
  end

  defp iterate(_repl, _query, _context, _llm, 0) do
    {:error, :max_iterations_reached}
  end

  defp iterate(repl, query, context, llm, iteration) do
    with {:ok, source_code} <- call_llm(llm, repl, query, iteration) do
      Logger.info("[Iteration #{iteration}] Script:\n#{source_code}")

      ExRLM.LuaRepl.eval(repl, source_code)
      |> case do
        {:halt, final_answer} ->
          Logger.info("[Iteration #{iteration}] Final answer: #{final_answer}")
          {:ok, final_answer}

        {:cont, repl} ->
          Logger.info("[Iteration #{iteration}] Output:\n#{last_output(repl)}")
          iterate(repl, query, context, llm, iteration - 1)
      end
    end
  end

  defp last_output(repl) do
    case hd(repl.history) do
      %Repl.Interaction{kind: :output, content: content} -> content
      _ -> ""
    end
  end

  defp call_llm(llm, repl, query, iteration) do
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

    case llm.(messages) do
      {:ok, %ExRLM.LLM.Response{content: content}} -> {:ok, content}
      {:error, _} = err -> err
    end
  end
end
