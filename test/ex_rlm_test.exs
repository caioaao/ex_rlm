defmodule ExRLMTest do
  use ExUnit.Case

  test "creates a new repl instance" do
    repl = ExRLM.new(model: "gpt-4")

    assert %ExRLM.Repl{} = repl
    assert repl.model == "gpt-4"
    assert repl.recursive_model == "gpt-4"
  end

  test "creates repl with different recursive model" do
    repl = ExRLM.new(model: "gpt-4", recursive_model: "gpt-4-mini")

    assert repl.model == "gpt-4"
    assert repl.recursive_model == "gpt-4-mini"
  end
end

defmodule ExRLM.LuaAnswerTest do
  use ExUnit.Case

  test "rlm.answer returns sentinel value with string" do
    lua = ExRLM.Lua.new(model: "test", max_depth: 1, completion_fn: fn _, _, _ -> "" end)

    {result, _lua} = Lua.eval!(lua, ~s[return rlm.answer("The answer is 42")])

    assert result == ["__rlm_final_answer__", "The answer is 42"]
  end

  test "rlm.answer returns sentinel value with variable" do
    lua = ExRLM.Lua.new(model: "test", max_depth: 1, completion_fn: fn _, _, _ -> "" end)

    {result, _lua} =
      Lua.eval!(lua, """
        my_result = "computed value"
        return rlm.answer(my_result)
      """)

    assert result == ["__rlm_final_answer__", "computed value"]
  end

  test "rlm.answer returns sentinel value with number" do
    lua = ExRLM.Lua.new(model: "test", max_depth: 1, completion_fn: fn _, _, _ -> "" end)

    {result, _lua} = Lua.eval!(lua, "return rlm.answer(42)")

    assert result == ["__rlm_final_answer__", 42.0]
  end

  test "rlm.answer returns sentinel value with nil" do
    lua = ExRLM.Lua.new(model: "test", max_depth: 1, completion_fn: fn _, _, _ -> "" end)

    {result, _lua} = Lua.eval!(lua, "return rlm.answer(nil)")

    assert result == ["__rlm_final_answer__", nil]
  end

  test "rlm.answer works with table values" do
    lua = ExRLM.Lua.new(model: "test", max_depth: 1, completion_fn: fn _, _, _ -> "" end)

    {result, _lua} = Lua.eval!(lua, ~s[return rlm.answer({a = 1, b = 2})])

    assert ["__rlm_final_answer__", table] = result
    assert is_list(table)
  end
end

defmodule ExRLM.LuaCompletionTest do
  use ExUnit.Case

  test "lua completion calls callback and decrements depth" do
    test_pid = self()

    completion_fn = fn query, context, config ->
      send(test_pid, {:called, query, context, config.max_depth})
      "response for: #{query}"
    end

    lua = ExRLM.Lua.new(model: "test", max_depth: 2, completion_fn: completion_fn)

    {[r1], lua} = Lua.eval!(lua, "return rlm.llm_query('q1', 'c1')")
    assert r1 == "response for: q1"
    assert_received {:called, "q1", "c1", 1}

    {[r2], lua} = Lua.eval!(lua, "return rlm.llm_query('q2', 'c2')")
    assert r2 == "response for: q2"
    assert_received {:called, "q2", "c2", 0}

    {[r3, err], _lua} = Lua.eval!(lua, "return rlm.llm_query('q3', 'c3')")
    assert r3 == nil
    assert err == "max recursion depth reached"
    refute_received {:called, "q3", _, _}
  end

  test "returns error immediately when max_depth is 0" do
    completion_fn = fn _q, _c, _config -> "should not be called" end

    lua = ExRLM.Lua.new(model: "test", max_depth: 0, completion_fn: completion_fn)

    {[result, err], _lua} = Lua.eval!(lua, "return rlm.llm_query('query', 'context')")

    assert result == nil
    assert err == "max recursion depth reached"
  end

  test "passes context correctly to completion function" do
    test_pid = self()

    completion_fn = fn query, context, _config ->
      send(test_pid, {:context_check, query, context})
      "done"
    end

    lua = ExRLM.Lua.new(model: "test", max_depth: 5, completion_fn: completion_fn)

    Lua.eval!(lua, """
      rlm.llm_query("my query", "detailed context here")
    """)

    assert_received {:context_check, "my query", "detailed context here"}
  end

  test "returns error when context exceeds max_context_chars" do
    completion_fn = fn _q, _c, _config -> "should not be called" end

    lua =
      ExRLM.Lua.new(
        model: "test",
        max_depth: 5,
        max_context_chars: 100,
        completion_fn: completion_fn
      )

    # Create context that exceeds the limit
    large_context = String.duplicate("x", 150)

    {[result, err], _lua} =
      Lua.eval!(lua, """
        return rlm.llm_query("query", "#{large_context}")
      """)

    assert result == nil
    assert err =~ "context too large"
    assert err =~ "limit is 100"
    assert err =~ "Split into chunks"
  end

  test "succeeds when context is within max_context_chars" do
    test_pid = self()

    completion_fn = fn query, context, _config ->
      send(test_pid, {:called, query, context})
      "success"
    end

    lua =
      ExRLM.Lua.new(
        model: "test",
        max_depth: 5,
        max_context_chars: 100,
        completion_fn: completion_fn
      )

    {[result], _lua} =
      Lua.eval!(lua, """
        return rlm.llm_query("q", "small context")
      """)

    assert result == "success"
    assert_received {:called, "q", "small context"}
  end

  test "error message includes actual size and suggested chunk size" do
    completion_fn = fn _q, _c, _config -> "should not be called" end

    lua =
      ExRLM.Lua.new(
        model: "test",
        max_depth: 5,
        max_context_chars: 1000,
        completion_fn: completion_fn
      )

    # Query of 100 chars + context of 1000 chars = 1100 total
    query = String.duplicate("q", 100)
    context = String.duplicate("c", 1000)

    {[result, err], _lua} =
      Lua.eval!(lua, """
        return rlm.llm_query("#{query}", "#{context}")
      """)

    assert result == nil
    assert err =~ "1100 chars"
    assert err =~ "query: 100"
    assert err =~ "context: 1000"
    assert err =~ "limit is 1000"
    assert err =~ "~500 chars"
  end
end
