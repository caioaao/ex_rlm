defmodule ExRLM.Lua.Completion do
  @moduledoc """
  Defines the Lua API for the REPL environment.

  This module registers Lua functions that the LLM can call:
  - `rlm.llm_query(query, context)` - perform recursive LLM completions
  - `rlm.answer(value)` - signal the final answer
  """

  use Lua.API, scope: "rlm"

  @doc """
  Signals the final answer from the REPL.

  Returns two values: a sentinel marker `"__rlm_final_answer__"` and the answer value.
  The REPL uses this to detect when the LLM has provided its final answer.

  ## Example

      return rlm.answer("The answer is 42")
      return rlm.answer(my_result_variable)
  """
  deflua answer(value), state do
    {["__rlm_final_answer__", value], state}
  end

  @doc """
  Lua-callable LLM query function.

  Returns the completion result, or `[nil, error_message]` if max recursion
  depth has been reached.
  """
  deflua llm_query(query, context), state do
    {:ok, config} = Lua.get_private(state, :rlm_config)

    if config.max_depth <= 0 do
      {[nil, "max recursion depth reached"], state}
    else
      # Decrement depth for recursive call
      new_config = %{config | max_depth: config.max_depth - 1}
      new_state = Lua.put_private(state, :rlm_config, new_config)

      # Call the completion function
      result = config.completion_fn.(query, context, new_config)
      {[result], new_state}
    end
  end
end
