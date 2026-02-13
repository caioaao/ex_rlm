defmodule ExRLM.Repl.Interaction do
  @moduledoc """
  Represents the interactions the LM had.
  """
  defstruct [:kind, :content]

  @truncation_length 100_000

  @type kind() :: :script | :output

  @type t() :: %__MODULE__{
          kind: kind(),
          content: String.t()
        }

  @doc """
  Turns the interaction into a string suitable for passing as context to an LLM
  """
  def format(%__MODULE__{kind: :script, content: content}) do
    "CODE:\n\n``lua\n#{content}\n```"
  end

  def format(%__MODULE__{kind: :output, content: content}) do
    content = maybe_trunc(content)
    "OUTPUT:\n\n```\n#{content}\n```"
  end

  defp maybe_trunc(content) do
    if String.length(content) > @truncation_length do
      {content, _} = String.split_at(content, @truncation_length)
      "#{content}..."
    else
      content
    end
  end
end
