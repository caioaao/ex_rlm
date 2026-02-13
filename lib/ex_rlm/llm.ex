defmodule ExRLM.LLM do
  @moduledoc """
  BAML client for LLM API calls.

  Exposes:
  - `repl_completion/5` - Main REPL completion with system prompt and iteration state
  - `llm_query/3` - Query for recursive sub-calls (matches Lua.Completion signature)
  """

  use BamlElixir.Client, path: {:ex_rlm, "priv/baml_src"}

  @doc """
  Main REPL completion call.

  Handles three states based on parameters:
  - iteration=0, final_answer=false: First interaction (ReplFirstIteration)
  - iteration>0, final_answer=false: Continue exploration (ReplContinue)
  - final_answer=true: Force final answer synthesis (ReplFinalAnswer)
  """
  @spec repl_completion(String.t(), String.t(), list(map()), integer(), boolean(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def repl_completion(query, context, history, iteration, final_answer, model) do
    opts = %{llm_client: client_for_model(model)}
    formatted_history = format_history(history)

    cond do
      final_answer ->
        __MODULE__.ReplFinalAnswer.call(%{query: query, history: formatted_history}, opts)

      iteration == 0 ->
        __MODULE__.ReplFirstIteration.call(%{query: query, context: context}, opts)

      true ->
        __MODULE__.ReplContinue.call(%{query: query, history: formatted_history}, opts)
    end
  end

  defp format_history([]), do: "(No previous iterations)"

  defp format_history(history) do
    history
    |> Enum.map(fn entry ->
      outcome_text =
        if entry.outcome == :success,
          do: "Result: #{entry.result}",
          else: "Error: #{entry.result}\nPlease fix the error and continue."

      """
      --- Iteration #{entry.iteration} ---
      Code:
      ```lua
      #{String.trim(entry.code)}
      ```
      #{outcome_text}
      """
    end)
    |> Enum.join("\n")
  end

  @doc """
  LLM query for recursive calls from Lua.

  Matches the signature expected by ExRLM.Lua.Completion's config.completion_fn
  """
  @spec llm_query(String.t(), String.t(), map()) :: String.t()
  def llm_query(query, context, config) do
    case __MODULE__.LlmQuery.call(
           %{query: query, context: context},
           %{llm_client: client_for_model(config.model)}
         ) do
      {:ok, result} -> result
      {:error, _reason} -> "Error: LLM query failed"
    end
  end

  @model_to_client %{
    "gpt-4o" => "GPT4o",
    "gpt-4o-mini" => "GPT4oMini",
    "gpt-4-turbo" => "GPT4Turbo",
    "gpt-4-turbo-preview" => "GPT4Turbo"
  }

  @default_client "GPT4o"

  defp client_for_model(model) when is_binary(model) do
    Map.get(@model_to_client, model, @default_client)
  end

  defp client_for_model(_), do: @default_client
end
