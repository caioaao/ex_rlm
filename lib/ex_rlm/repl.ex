defmodule ExRLM.Repl do
  @moduledoc """
  Responsible for instantiating the Lua engine, setting up the context, and querying the LLM.

  LLM responses are evaluated directly as Lua code. Final answers are detected via
  the sentinel value returned by `rlm.answer(value)`.
  """

  alias ExRLM.LLM

  defstruct [:lua_state, :model, :recursive_model, :max_iterations, :max_depth]

  @type t :: %__MODULE__{
          lua_state: term(),
          model: String.t(),
          recursive_model: String.t(),
          max_iterations: pos_integer(),
          max_depth: non_neg_integer()
        }

  @doc """
  Creates a new Repl instance with the given options.

  ## Options
    * `:model` - The primary model to use for completions (required)
    * `:recursive_model` - The model to use for recursive calls (defaults to `:model`)
    * `:max_iterations` - Maximum number of iterations (default: 10)
    * `:max_depth` - Maximum depth of recursion (default: 10)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    model = Keyword.fetch!(opts, :model)
    recursive_model = Keyword.get(opts, :recursive_model, model)
    max_iterations = Keyword.get(opts, :max_iterations, 10)
    max_depth = Keyword.get(opts, :max_depth, 10)

    lua_state =
      ExRLM.Lua.new(
        model: recursive_model,
        max_iterations: max_iterations,
        max_depth: max_depth,
        completion_fn: &LLM.llm_query/3
      )

    %__MODULE__{
      lua_state: lua_state,
      model: model,
      recursive_model: recursive_model,
      max_iterations: max_iterations,
      max_depth: max_depth
    }
  end

  @doc """
  Runs a completion query through the LLM with Lua execution.

  ## Options
    * `:context` - Additional context for the query
  """
  @max_consecutive_errors 3

  @spec completion(t(), String.t(), keyword()) :: {:ok, {t(), String.t()}} | {:error, term()}
  def completion(repl, query, opts \\ []) do
    context = Keyword.get(opts, :context, "")

    # Set context variable in Lua
    lua_state = Lua.set!(repl.lua_state, [:context], context)
    repl = %{repl | lua_state: lua_state}

    # Start iteration loop
    iterate(repl, query, context, 0, 0)
  end

  # Main iteration loop - continues until FINAL or max_iterations
  defp iterate(repl, query, context, iteration, consecutive_errors)
       when iteration < repl.max_iterations and consecutive_errors < @max_consecutive_errors do
    with {:ok, response} <- LLM.repl_completion(query, context, iteration, false, repl.model) do
      process_response(repl, query, response, context, iteration, consecutive_errors)
    end
  end

  # Max iterations reached - force final answer
  defp iterate(repl, query, context, _iteration, _consecutive_errors) do
    with {:ok, response} <- LLM.repl_completion(query, context, 0, true, repl.model) do
      case execute_response(repl.lua_state, response) do
        {:final_answer, answer, new_lua_state} ->
          {:ok, {%{repl | lua_state: new_lua_state}, answer}}

        {:continue, result, _new_lua_state} ->
          # If LLM still doesn't provide rlm.answer(), return the result
          {:ok, {repl, result}}

        {:error, _error_msg, _lua_state} ->
          # If there's a Lua error, return raw response
          {:ok, {repl, response}}
      end
    end
  end

  defp process_response(repl, query, response, context, iteration, consecutive_errors) do
    case execute_response(repl.lua_state, response) do
      {:final_answer, answer, new_lua_state} ->
        {:ok, {%{repl | lua_state: new_lua_state}, answer}}

      {:continue, result, new_lua_state} ->
        new_context = append_to_context(context, iteration, response, result)
        new_repl = %{repl | lua_state: new_lua_state}
        iterate(new_repl, query, new_context, iteration + 1, 0)

      {:error, error_msg, lua_state} ->
        new_context = append_error_to_context(context, iteration, response, error_msg)
        new_repl = %{repl | lua_state: lua_state}
        iterate(new_repl, query, new_context, iteration + 1, consecutive_errors + 1)
    end
  end

  defp execute_response(lua_state, response) do
    try do
      case Lua.eval!(lua_state, response) do
        {["__rlm_final_answer__", answer], new_state} ->
          {:final_answer, format_result(answer), new_state}

        {result, new_state} ->
          {:continue, format_result(result), new_state}
      end
    rescue
      e in [Lua.RuntimeException, Lua.CompilerException] ->
        {:error, Exception.message(e), lua_state}
    end
  end

  defp append_to_context(context, iteration, response, result) do
    context <>
      "\n\n--- Iteration #{iteration} ---\n" <>
      "Code:\n```lua\n#{String.trim(response)}\n```\n" <>
      "Result: #{result}"
  end

  defp append_error_to_context(context, iteration, response, error_msg) do
    context <>
      "\n\n--- Iteration #{iteration} ---\n" <>
      "Code:\n```lua\n#{String.trim(response)}\n```\n" <>
      "Error: #{error_msg}\n" <>
      "Please fix the Lua syntax error and try again."
  end

  defp format_result(nil), do: "nil"
  defp format_result([]), do: "[]"
  defp format_result(value) when is_list(value), do: inspect(value)
  defp format_result(value) when is_binary(value), do: value
  defp format_result(value), do: inspect(value)
end
