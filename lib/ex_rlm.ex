defmodule ExRLM do
  @moduledoc """
  An Elixir implementation of the RLM inference strategy using a Lua engine.
  """

  defdelegate new(opts), to: ExRLM.Repl
  defdelegate completion(repl, query, opts), to: ExRLM.Repl

  def completion(repl, query), do: completion(repl, query, [])
end
