defmodule ExRLM.LLM do
  @moduledoc """
  Type definitions and callback contract for LLM providers.

  ## The LLM Callback

  An LLM is represented as a function with the following signature:

      @type t() :: (list(Message.t()) -> {:ok, Response.t()} | {:error, term()})

  The function receives a list of messages and must return either:
    * `{:ok, %Response{content: "...", usage: %Usage{...}}}` on success
    * `{:error, reason}` on failure

  ## Implementing a Custom Provider

  See `ExRLM.Completion.OpenAI` for a reference implementation. Your provider must:

  1. Accept a list of `Message` structs (each with `:role` and `:content`)
  2. Return a `Response` struct with the completion content and token usage

  Example:

      def my_provider(messages) do
        # Convert messages to your API format
        # Make API call
        # Return {:ok, %Response{...}} or {:error, reason}
      end

      {:ok, answer} = ExRLM.completion("Your query", llm: &my_provider/1)

  ## Types

  This module defines three struct types:
    * `ExRLM.LLM.Message` - Input message with `:role` and `:content`
    * `ExRLM.LLM.Response` - Output with `:content` and `:usage`
    * `ExRLM.LLM.Usage` - Token counts
  """

  alias ExRLM.LLM
  @type t() :: (list(LLM.Message.t()) -> {:ok, LLM.Response.t()} | {:error, term()})
end

defmodule ExRLM.LLM.Message do
  @moduledoc """
  Represents a message in the LLM conversation.

  ## Fields

    * `:role` - Either `"system"` or `"user"`
    * `:content` - The message content as a string
  """
  defstruct [:role, :content]

  @type t :: %__MODULE__{
          role: String.t(),
          content: String.t()
        }
end

defmodule ExRLM.LLM.Usage do
  @moduledoc """
  Token usage statistics from an LLM call.

  ## Fields

    * `:prompt_tokens` - Tokens in the input prompt
    * `:completion_tokens` - Tokens in the generated response
    * `:total_tokens` - Sum of prompt and completion tokens
  """
  defstruct [:prompt_tokens, :completion_tokens, :total_tokens]

  @type t :: %__MODULE__{
          prompt_tokens: integer(),
          completion_tokens: integer(),
          total_tokens: integer()
        }
end

defmodule ExRLM.LLM.Response do
  @moduledoc """
  Response from an LLM provider.

  ## Fields

    * `:content` - The generated text response
    * `:usage` - Token usage statistics (`ExRLM.LLM.Usage`)
  """
  defstruct [:content, :usage]

  @type t :: %__MODULE__{
          content: String.t(),
          usage: ExRLM.LLM.Usage.t()
        }
end
