defmodule ExRLM.Repl.Interaction do
  @moduledoc false
  defstruct [:kind, :content]

  @type kind() :: :script | :output

  @type t() :: %__MODULE__{
          kind: kind(),
          content: String.t()
        }
end
