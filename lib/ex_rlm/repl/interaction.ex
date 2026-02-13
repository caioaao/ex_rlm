defmodule ExRLM.Repl.Interaction do
  @moduledoc """
  Represents the interactions the LM had.
  """
  defstruct [:kind, :content]

  @type kind() :: :script | :output

  @type t() :: %__MODULE__{
          kind: kind(),
          content: String.t()
        }
end
