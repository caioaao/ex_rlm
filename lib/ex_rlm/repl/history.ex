defmodule ExRLM.Repl.History do
  alias ExRLM.Repl.Interaction

  @truncation_length 100_000

  @type t() :: list(Interaction.t())

  def new(), do: []

  def push(history, kind, content),
    do: [%Interaction{kind: kind, content: content} | history]

  def format(history) do
    [
      "<repl_history>\n",
      history |> Enum.reverse() |> Enum.map(&format_interaction/1),
      "</repl_history>"
    ]
    |> IO.iodata_to_binary()
  end

  defp format_interaction(%Interaction{kind: :script, content: content}) do
    [
      "  <code lang=\"lua\">\n",
      indent_lines(content, "    "),
      "  </code>\n"
    ]
  end

  defp format_interaction(%Interaction{kind: :output, content: content}) do
    [
      "  <output>\n",
      indent_lines(maybe_trunc(content), "    "),
      "  </output>\n"
    ]
  end

  defp indent_lines(content, prefix) do
    content
    |> String.split("\n")
    |> Enum.map(&[prefix, &1, "\n"])
  end

  defp maybe_trunc(content) do
    if String.length(content) > @truncation_length do
      {content, _} = String.split_at(content, @truncation_length)
      content <> "..."
    else
      content
    end
  end
end
