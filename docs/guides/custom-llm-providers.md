# Custom LLM Providers

This guide shows how to implement custom LLM providers for ExRLM.

## The LLM Callback Contract

An LLM provider is a function with this signature:

```elixir
@type t() :: (list(Message.t()) -> {:ok, Response.t()} | {:error, term()})
```

Where:
- **Input**: A list of `%ExRLM.LLM.Message{role: "system" | "user", content: "..."}`
- **Output**: `{:ok, %ExRLM.LLM.Response{content: "...", usage: %Usage{...}}}` or `{:error, reason}`

## Implementing a Provider

### Example: Anthropic Claude

```elixir
defmodule MyApp.Anthropic do
  alias ExRLM.LLM.{Message, Response, Usage}

  def new(model \\ "claude-sonnet-4-20250514") do
    fn messages -> complete(messages, model) end
  end

  def complete(messages, model) do
    # Convert ExRLM messages to Anthropic format
    {system, user_messages} = extract_system(messages)

    body = %{
      model: model,
      max_tokens: 4096,
      system: system,
      messages: Enum.map(user_messages, &to_anthropic_message/1)
    }

    case make_request(body) do
      {:ok, %{"content" => [%{"text" => text} | _], "usage" => usage}} ->
        {:ok, %Response{
          content: text,
          usage: %Usage{
            prompt_tokens: usage["input_tokens"],
            completion_tokens: usage["output_tokens"],
            total_tokens: usage["input_tokens"] + usage["output_tokens"]
          }
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_system(messages) do
    case Enum.split_with(messages, &(&1.role == "system")) do
      {[%{content: system} | _], rest} -> {system, rest}
      {[], rest} -> {"", rest}
    end
  end

  defp to_anthropic_message(%Message{role: role, content: content}) do
    %{role: role, content: content}
  end

  defp make_request(body) do
    # Your HTTP client implementation
    # POST to https://api.anthropic.com/v1/messages
  end
end
```

### Using Your Provider

```elixir
rlm = ExRLM.new(%{llm: MyApp.Anthropic.new("claude-sonnet-4-20250514")})

{:ok, answer} = ExRLM.completion(rlm, "Analyze this", context: ctx)
```

## Testing Your Provider

Create a simple test to verify the contract:

```elixir
defmodule MyApp.AnthropicTest do
  use ExUnit.Case

  alias ExRLM.LLM.{Message, Response, Usage}

  test "returns valid response structure" do
    llm = MyApp.Anthropic.new()

    messages = [
      %Message{role: "system", content: "You are helpful."},
      %Message{role: "user", content: "Say hello."}
    ]

    assert {:ok, %Response{content: content, usage: %Usage{}}} = llm.(messages)
    assert is_binary(content)
  end
end
```

## Error Handling Patterns

Your provider should handle common failure modes:

```elixir
def complete(messages, model) do
  case make_request(body) do
    {:ok, %{status: 200, body: body}} ->
      parse_success(body)

    {:ok, %{status: 429}} ->
      {:error, :rate_limited}

    {:ok, %{status: 401}} ->
      {:error, :unauthorized}

    {:ok, %{status: status, body: body}} ->
      {:error, {:api_error, status, body}}

    {:error, %Tesla.Error{reason: :timeout}} ->
      {:error, :timeout}

    {:error, reason} ->
      {:error, {:request_failed, reason}}
  end
end
```

## Local Models

You can also use local models (e.g., via Ollama):

```elixir
defmodule MyApp.Ollama do
  alias ExRLM.LLM.{Message, Response, Usage}

  def new(model \\ "llama3.2") do
    fn messages -> complete(messages, model) end
  end

  def complete(messages, model) do
    body = %{
      model: model,
      messages: Enum.map(messages, &Map.from_struct/1),
      stream: false
    }

    case Tesla.post(client(), "/api/chat", body) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        {:ok, %Response{
          content: content,
          usage: %Usage{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, "http://localhost:11434"},
      Tesla.Middleware.JSON
    ])
  end
end
```
