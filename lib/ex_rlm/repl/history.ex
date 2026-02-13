defmodule ExRLM.Repl.History do
  alias ExRLM.Repl
  @type t() :: list(Repl.Interaction.t())

  def new(), do: []

  def push(history, kind, content),
    do: [%Repl.Interaction{kind: kind, content: content} | history]

  def format(history) do
    Enum.reverse(history)
    |> Enum.map_join("\n", &Repl.Interaction.format/1)
  end
end
