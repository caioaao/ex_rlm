defmodule ExRLM.LLM do
  alias ExRLM.LLM
  @type t() :: (list(LLM.Message.t()) -> {:ok, LLM.Response.t()} | {:error, term()})
end

defmodule ExRLM.LLM.Message do
  defstruct [:role, :content]

  @type t :: %__MODULE__{
          role: String.t(),
          content: String.t()
        }
end

defmodule ExRLM.LLM.Usage do
  defstruct [:prompt_tokens, :completion_tokens, :total_tokens]

  @type t :: %__MODULE__{
          prompt_tokens: integer(),
          completion_tokens: integer(),
          total_tokens: integer()
        }
end

defmodule ExRLM.LLM.Response do
  defstruct [:content, :usage]

  @type t :: %__MODULE__{
          content: String.t(),
          usage: ExRLM.LLM.Usage.t()
        }
end
