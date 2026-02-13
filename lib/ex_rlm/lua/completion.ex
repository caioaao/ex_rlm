defmodule ExRLM.Lua.Completion do
  @moduledoc """
  Defines the Lua API for the REPL environment.

  This module registers Lua functions that the LLM can call:
  - `rlm.llm_query(query, context)` - perform recursive LLM completions
  """

  use Lua.API, scope: "rlm"

  @doc """
  Lua-callable LLM query function.

  Always returns a tuple `(result, error)`:
  - On success: `(result, nil)`
  - On error: `(nil, error_message)`

  This consistent return format allows Lua code to always destructure:
  `local result, err = rlm.llm_query(query, context)`
  """
  deflua llm_query(query, context), state do
    {:ok, completion} = Lua.get_private(state, :completion_fn)

    case completion.(query, context) do
      {:ok, result} ->
        {[result, nil], state}

      {:error, :max_depth_reached} ->
        {[nil, "max recursion depth reached"], state}

      {:error, :max_iterations_reached} ->
        {[nil, "max number of iterations reached"], state}

      {:error, error} ->
        {[nil, "unexpected error occurred: #{inspect(error)}"], state}
    end
  end
end
