defmodule ExRLM.Lua.Completion do
  @moduledoc """
  Defines the Lua API for recursively calling the completion API.

  This module registers Lua functions that the LLM can call to perform
  recursive completions.
  """

  @doc """
  Registers the completion functions in the Lua state.
  """
  @spec register(term()) :: {:ok, term()} | {:error, term()}
  def register(lua_state) do
    # TODO: Register completion function in Lua
    {:ok, lua_state}
  end
end
