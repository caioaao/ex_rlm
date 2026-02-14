defmodule ExRLM.TestHelpers do
  @moduledoc """
  Test helpers and mock builders for ExRLM tests.
  """

  alias ExRLM.LLM

  @doc """
  Creates a mock LLM function that returns canned responses in sequence.
  Uses an Agent to track state across calls.

  ## Example

      responses = [
        {:ok, llm_response("print('step 1')")},
        {:ok, llm_response("return 'done'")}
      ]
      llm = mock_llm(responses)
  """
  def mock_llm(responses) when is_list(responses) do
    {:ok, agent} = Agent.start_link(fn -> responses end)

    fn _messages ->
      Agent.get_and_update(agent, fn
        [response | rest] -> {response, rest}
        [] -> {{:error, :no_more_responses}, []}
      end)
    end
  end

  @doc """
  Creates a mock LLM that always returns the same response.

  ## Example

      llm = static_llm("return 42")
      {:ok, answer} = ExRLM.completion("query", llm: llm)
  """
  def static_llm(content) when is_binary(content) do
    fn _messages -> {:ok, llm_response(content)} end
  end

  @doc """
  Creates a mock LLM that always returns an error.

  ## Example

      llm = error_llm(:rate_limit)
      assert {:error, :rate_limit} = ExRLM.completion(rlm, "query")
  """
  def error_llm(error_term) do
    fn _messages -> {:error, error_term} end
  end

  @doc """
  Creates a mock LLM that captures messages for later inspection.
  Returns a tuple of {llm_fn, get_captured_fn}.

  ## Example

      {llm, get_captured} = capture_llm("return 'test'")
      ExRLM.completion("query", llm: llm)
      messages = get_captured.()
  """
  def capture_llm(content) when is_binary(content) do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    llm = fn messages ->
      Agent.update(agent, fn captured -> [messages | captured] end)
      {:ok, llm_response(content)}
    end

    get_captured = fn -> Agent.get(agent, &Enum.reverse/1) end

    {llm, get_captured}
  end

  @doc """
  Builds an LLM.Response struct with the given content.
  """
  def llm_response(content) do
    %LLM.Response{
      content: content,
      usage: %LLM.Usage{
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15
      }
    }
  end

  @doc """
  Creates a LuaRepl instance with a no-op completion function.
  """
  def create_repl(context \\ []) do
    completion_fn = fn _query, _ctx -> {:error, :not_implemented} end
    ExRLM.LuaRepl.new(completion_fn, context)
  end

  @doc """
  Creates a LuaRepl instance with a custom completion function.
  """
  def create_repl_with_completion(completion_fn, context \\ []) do
    ExRLM.LuaRepl.new(completion_fn, context)
  end

  @doc """
  Generates a string of given size for truncation tests.
  """
  def large_string(size) do
    String.duplicate("x", size)
  end
end
