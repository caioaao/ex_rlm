defmodule ExRLM do
  @moduledoc """
  An Elixir implementation of the RLM inference strategy using a Lua engine.
  """
  alias ExRLM.LLM
  alias ExRLM.Repl

  defstruct [:config, history: []]

  @type context() :: list(String.t())

  @type config() :: %{
          model: String.t()
        }

  # TODO: strengthen model types
  @type t() :: %__MODULE__{config: config()}

  @spec new(config()) :: t()
  def new(config) do
    %__MODULE__{config: config}
  end

  @type completion_opt() ::
          {:max_depth, pos_integer()}
          | {:max_iterations, pos_integer()}
          | {:context, context()}

  @spec completion(t(), String.t(), keyword(completion_opt())) ::
          {:ok, {String.t(), t()}} | {:error, term()}
  def completion(rlm, query, opts \\ []) do
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
      ExRLM.LuaRepl.eval(repl, source_code)
      |> case do
        {:halt, final_answer} -> {:ok, final_answer}
        {:cont, repl} -> iterate(rlm, repl, query, context, iteration - 1)
      end
    end
  end

  defp call_llm(rlm, repl, query, iteration) do
    repl_history = Repl.History.format(repl.history)
    model = rlm.config.model

    if iteration > 1 do
      LLM.ReplCompletion.call(%{query: query, repl_history: repl_history}, %{llm_client: model})
    else
      LLM.ReplFinalAnswer.call(%{query: query, repl_history: repl_history}, %{llm_client: model})
    end
  end
end
