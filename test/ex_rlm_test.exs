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
end
