defmodule ExRLM.Repl do
  @moduledoc """
  Responsible for instantiating the Lua engine, setting up the context, and querying the LLM.
  """

  alias ExRLM.LLM
  alias ExRLM.Repl.Parser

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
      case Parser.parse_response(response) do
        {:final_text, text} ->
          {:ok, {repl, text}}

        {:final_var, var} ->
          resolve_final_var(repl, var)

        _ ->
          # If LLM still doesn't provide FINAL, return raw response
          {:ok, {repl, response}}
      end
    end
  end

  defp process_response(repl, query, response, context, iteration, consecutive_errors) do
    case Parser.parse_response(response) do
      {:final_text, text} ->
        {:ok, {repl, text}}

      {:final_var, var} ->
        resolve_final_var(repl, var)

      {:code_blocks, blocks, remaining_text} ->
        case execute_code_blocks(repl, blocks, iteration) do
          {:ok, results, new_repl} ->
            new_context = append_to_context(context, iteration, blocks, results, remaining_text)
            iterate(new_repl, query, new_context, iteration + 1, 0)

          {:error, error_msg, new_repl} ->
            new_context = append_error_to_context(context, iteration, error_msg)
            iterate(new_repl, query, new_context, iteration + 1, consecutive_errors + 1)
        end

      {:continue, text} ->
        new_context = context <> "\n\n--- Iteration #{iteration} ---\n" <> text
        iterate(repl, query, new_context, iteration + 1, 0)
    end
  end

  defp execute_code_blocks(repl, blocks, _iteration) do
    Enum.reduce_while(blocks, {:ok, [], repl}, fn code, {:ok, results, current_repl} ->
      case execute_code_block(current_repl.lua_state, code) do
        {:ok, result, new_lua_state} ->
          new_repl = %{current_repl | lua_state: new_lua_state}
          {:cont, {:ok, results ++ [{code, {:ok, result}}], new_repl}}

        {:error, error_msg, lua_state} ->
          new_repl = %{current_repl | lua_state: lua_state}
          {:halt, {:error, error_msg, new_repl}}
      end
    end)
  end

  defp execute_code_block(lua_state, code) do
    try do
      {results, new_state} = Lua.eval!(lua_state, code)
      {:ok, results, new_state}
    rescue
      e in [Lua.RuntimeException, Lua.CompilerException] ->
        {:error, Exception.message(e), lua_state}
    end
  end

  defp resolve_final_var(repl, var) do
    try do
      value = Lua.get!(repl.lua_state, [String.to_atom(var)])
      {:ok, {repl, format_result(value)}}
    rescue
      _ -> {:error, {:final_var_not_found, var}}
    end
  end

  defp append_to_context(context, iteration, blocks, results, remaining_text) do
    code_results =
      Enum.zip(blocks, results)
      |> Enum.map(fn {code, {_code, {:ok, result}}} ->
        """
        Code:
        ```lua
        #{String.trim(code)}
        ```
        Result: #{format_result(result)}
        """
      end)
      |> Enum.join("\n")

    context <>
      "\n\n--- Iteration #{iteration} ---\n" <>
      remaining_text <>
      "\n" <>
      code_results
  end

  defp append_error_to_context(context, iteration, error_msg) do
    context <>
      "\n\n--- Iteration #{iteration} ---\n" <>
      "Error executing Lua code: #{error_msg}\n" <>
      "Please fix the error and try again."
  end

  defp format_result(nil), do: "nil"
  defp format_result([]), do: "[]"
  defp format_result(value) when is_list(value), do: inspect(value)
  defp format_result(value) when is_binary(value), do: value
  defp format_result(value), do: inspect(value)
end
