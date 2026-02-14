defmodule ExRLM.Completion.OpenAI do
  @moduledoc """
  OpenAI API completion provider using Tesla + Mint.
  """

  @doc """
  Creates an LLM function configured with the given model.

  ## Examples

      llm = ExRLM.Completion.OpenAI.new("gpt-4o-mini")
      {:ok, answer} = ExRLM.completion("Your query", llm: llm)

  """
  alias ExRLM.LLM.{Message, Response, Usage}

  @timeout to_timeout(minute: 5)

  @spec new(String.t()) :: ExRLM.LLM.t()
  def new(model \\ "gpt-4o") do
    fn messages -> complete(messages, model) end
  end

  @doc """
  Sends a completion request to OpenAI.
  """
  @spec complete([Message.t()], String.t()) ::
          {:ok, Response.t()} | {:error, term()}
  def complete(messages, model \\ "gpt-4o") do
    # Convert structs to maps for the API
    messages_for_api = Enum.map(messages, &Map.from_struct/1)
    body = %{model: model, messages: messages_for_api}

    case Tesla.post(client(), "/chat/completions", body) do
      {:ok,
       %{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => content}} | _], "usage" => usage}
       }} ->
        {:ok, %Response{content: content, usage: normalize_usage(usage)}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp client do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
        Tesla.Middleware.JSON,
        {Tesla.Middleware.Headers, [{"authorization", "Bearer #{api_key()}"}]},
        {Tesla.Middleware.Timeout, timeout: @timeout}
      ],
      # we use http1 to avoid issues when request body is large: https://github.com/elixir-tesla/tesla/issues/394#issuecomment-1092792890
      {Tesla.Adapter.Mint, timeout: @timeout, protocols: [:http1]}
    )
  end

  defp api_key do
    System.get_env("OPENAI_API_KEY") ||
      raise "OPENAI_API_KEY environment variable is not set"
  end

  defp normalize_usage(usage) do
    %Usage{
      prompt_tokens: usage["prompt_tokens"],
      completion_tokens: usage["completion_tokens"],
      total_tokens: usage["total_tokens"]
    }
  end
end
