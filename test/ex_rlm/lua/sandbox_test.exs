defmodule ExRLM.Lua.SandboxTest do
  use ExUnit.Case

  describe "blocked dangerous functions" do
    setup do
      lua = ExRLM.Lua.new(model: "test", completion_fn: fn _, _, _ -> "ok" end)
      {:ok, lua: lua}
    end

    test "blocks debug library", %{lua: lua} do
      # debug module is nil'd out, so accessing it raises "invalid index"
      assert_raise Lua.RuntimeException, fn ->
        Lua.eval!(lua, "return debug.getinfo(1)")
      end
    end

    test "blocks rawget", %{lua: lua} do
      assert_raise Lua.RuntimeException, ~r/sandboxed/, fn ->
        Lua.eval!(lua, "return rawget(_G, 'os')")
      end
    end

    test "blocks rawset", %{lua: lua} do
      assert_raise Lua.RuntimeException, ~r/sandboxed/, fn ->
        Lua.eval!(lua, "rawset({}, 'a', 1)")
      end
    end

    test "blocks getmetatable", %{lua: lua} do
      assert_raise Lua.RuntimeException, ~r/sandboxed/, fn ->
        Lua.eval!(lua, "return getmetatable('')")
      end
    end

    test "blocks setmetatable", %{lua: lua} do
      assert_raise Lua.RuntimeException, ~r/sandboxed/, fn ->
        Lua.eval!(lua, "setmetatable({}, {})")
      end
    end

    test "blocks collectgarbage", %{lua: lua} do
      assert_raise Lua.RuntimeException, ~r/sandboxed/, fn ->
        Lua.eval!(lua, "collectgarbage()")
      end
    end

    test "blocks coroutine library", %{lua: lua} do
      # coroutine module is nil'd out, so accessing it raises "invalid index"
      assert_raise Lua.RuntimeException, fn ->
        Lua.eval!(lua, "coroutine.create(function() end)")
      end
    end
  end

  describe "library default blocks (verification)" do
    setup do
      lua = ExRLM.Lua.new(model: "test", completion_fn: fn _, _, _ -> "ok" end)
      {:ok, lua: lua}
    end

    test "blocks io library", %{lua: lua} do
      # io module is nil'd out
      assert_raise Lua.RuntimeException, fn ->
        Lua.eval!(lua, "io.open('/etc/passwd', 'r')")
      end
    end

    test "blocks os.execute", %{lua: lua} do
      assert_raise Lua.RuntimeException, ~r/sandboxed/, fn ->
        Lua.eval!(lua, "os.execute('echo pwned')")
      end
    end

    test "blocks require", %{lua: lua} do
      assert_raise Lua.RuntimeException, ~r/sandboxed/, fn ->
        Lua.eval!(lua, "require('os')")
      end
    end

    test "blocks load", %{lua: lua} do
      assert_raise Lua.RuntimeException, ~r/sandboxed/, fn ->
        Lua.eval!(lua, "load('return 1')()")
      end
    end

    test "blocks dofile", %{lua: lua} do
      assert_raise Lua.RuntimeException, ~r/sandboxed/, fn ->
        Lua.eval!(lua, "dofile('/tmp/evil.lua')")
      end
    end
  end

  describe "safe functions remain available" do
    setup do
      lua = ExRLM.Lua.new(model: "test", completion_fn: fn _, _, _ -> "ok" end)
      {:ok, lua: lua}
    end

    test "math library works", %{lua: lua} do
      {[result], _} = Lua.eval!(lua, "return math.max(1, 5, 3)")
      assert result == 5
    end

    test "string library works", %{lua: lua} do
      {[result], _} = Lua.eval!(lua, "return string.upper('hello')")
      assert result == "HELLO"
    end

    test "table library works", %{lua: lua} do
      {[result], _} = Lua.eval!(lua, "return table.concat({'a', 'b', 'c'}, '-')")
      assert result == "a-b-c"
    end

    test "type function works", %{lua: lua} do
      {[result], _} = Lua.eval!(lua, "return type(42)")
      assert result == "number"
    end

    test "tostring/tonumber work", %{lua: lua} do
      {[result], _} = Lua.eval!(lua, "return tonumber('42') + 1")
      assert result == 43
    end

    test "pairs/ipairs work", %{lua: lua} do
      {[result], _} =
        Lua.eval!(lua, """
        local sum = 0
        for _, v in ipairs({1, 2, 3}) do
          sum = sum + v
        end
        return sum
        """)

      assert result == 6
    end

    test "local functions work", %{lua: lua} do
      {[result], _} =
        Lua.eval!(lua, """
        local function add(a, b)
          return a + b
        end
        return add(2, 3)
        """)

      assert result == 5
    end

    test "os.time is available", %{lua: lua} do
      {[result], _} = Lua.eval!(lua, "return os.time()")
      assert is_number(result)
      assert result > 0
    end

    test "os.date is available", %{lua: lua} do
      {[result], _} = Lua.eval!(lua, "return os.date('%Y')")
      assert is_binary(result)
    end
  end

  describe "rlm API works after sandboxing" do
    test "rlm.llm_query still works" do
      test_pid = self()

      completion_fn = fn query, context, _config ->
        send(test_pid, {:called, query, context})
        "response"
      end

      lua = ExRLM.Lua.new(model: "test", max_depth: 5, completion_fn: completion_fn)

      {[result], _} = Lua.eval!(lua, "return rlm.llm_query('test query', 'test context')")

      assert result == "response"
      assert_received {:called, "test query", "test context"}
    end
  end

  describe "sandbox escape attempts" do
    setup do
      lua = ExRLM.Lua.new(model: "test", completion_fn: fn _, _, _ -> "ok" end)
      {:ok, lua: lua}
    end

    test "cannot access debug via _G indexing", %{lua: lua} do
      # debug is nil'd out, so _G['debug'] returns nil
      assert_raise Lua.RuntimeException, fn ->
        Lua.eval!(lua, "_G['debug']['getinfo'](1)")
      end
    end

    test "cannot access debug via string concatenation", %{lua: lua} do
      # debug is nil'd out, so _G['deb'..'ug'] returns nil
      assert_raise Lua.RuntimeException, fn ->
        Lua.eval!(lua, "_G['deb' .. 'ug']['get' .. 'info'](1)")
      end
    end
  end
end
