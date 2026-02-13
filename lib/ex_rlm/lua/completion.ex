defmodule ExRLM.Lua.Completion do
  @moduledoc """
  Defines the Lua API for recursively calling the completion API.

  This module registers Lua functions that the LLM can call to perform
  recursive completions. The function is available in Lua as
  `rlm.llm_query(query, context)`.
  """

  use Lua.API, scope: "rlm"

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
