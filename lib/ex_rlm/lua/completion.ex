defmodule ExRLM.Lua.Completion do
  @moduledoc """
  Lua API for the RLM REPL environment.

  This module defines the functions available to the LLM in the Lua environment.

  ## Lua API Reference

  ### `return value`

  Returns the final answer and ends the session. Accepts strings, numbers, tables, or nil.

      -- When the LLM is ready to respond
      return "The main theme is..."

  ### `rlm.llm_query(query, context)`

  Spawns a recursive sub-query to analyze a chunk of context. Returns a tuple `(result, error)`:

      -- Always destructure the result
      local result, err = rlm.llm_query("Summarize this section", chunk)

      if err then
        print("Error: " .. err)  -- Handle error
      elseif result then
        -- Use result
      end

  **Error messages:**
  - `"max recursion depth reached"` - Hit the `max_depth` limit
  - `"max number of iterations reached"` - Hit the `max_iterations` limit
  - `"unexpected error occurred: ..."` - Other errors

  ### `print(value)`

  Output values to see in the next iteration. Useful for debugging and inspecting intermediate results.

      print("Context size: " .. #context)
      print("First 100 chars: " .. string.sub(context, 1, 100))

  ### Global Variables

  Variables assigned without `local` persist across iterations:

      -- First iteration
      results = {}  -- Global, persists

      -- Second iteration
      table.insert(results, chunk_result)  -- Still accessible

  The `context` global contains the context string passed to `ExRLM.completion/3`.
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
