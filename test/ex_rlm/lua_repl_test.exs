defmodule ExRLM.LuaReplTest do
  use ExUnit.Case, async: true

  import ExRLM.TestHelpers

  alias ExRLM.LuaRepl
  alias ExRLM.Repl.Interaction

  describe inspect(&LuaRepl.new/2) do
    test "initializes with empty history" do
      repl = create_repl()
      assert repl.history == []
    end

    test "context variable accessible in Lua" do
      context = ["item1", "item2", "item3"]
      repl = create_repl(context)

      assert {:cont, repl} = LuaRepl.eval(repl, "print(context[1])")
      [output | _] = repl.history
      assert output.content =~ "item1"
    end

    test "context as string accessible in Lua" do
      repl = create_repl("test context string")

      assert {:cont, repl} = LuaRepl.eval(repl, "print(context)")
      [output | _] = repl.history
      assert output.content =~ "test context string"
    end
  end

  describe inspect(&LuaRepl.eval/2) do
    test "script with no return value continues with print output captured" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "print('hello')")

      [output, script] = repl.history
      assert %Interaction{kind: :script, content: "print('hello')"} = script
      assert %Interaction{kind: :output, content: content} = output
      assert content =~ "hello"
    end

    test "script with single return value halts" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return 42")
      assert answer == "42"
    end

    test "script with string return value halts with quoted string" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return 'hello world'")
      assert answer == "\"hello world\""
    end

    test "script with multiple return values halts with list" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return 1, 2, 3")
      assert answer == "[1, 2, 3]"
    end

    test "script with table return value halts" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return {a = 1, b = 2}")
      # Tables are inspected
      assert is_binary(answer)
    end

    test "empty script continues without error" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "")
      [output, script] = repl.history
      assert script.content == ""
      assert output.content == ""
    end

    test "whitespace-only script continues without error" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "   \n\t  ")
      assert {:cont, _repl} = LuaRepl.eval(repl, "-- just a comment")
    end

    test "multiple print calls accumulated with tabs and newlines" do
      repl = create_repl()

      script = """
      print('first')
      print('second')
      print('third')
      """

      assert {:cont, repl} = LuaRepl.eval(repl, script)
      [output | _] = repl.history

      assert output.content =~ "first"
      assert output.content =~ "second"
      assert output.content =~ "third"
    end

    test "print with multiple arguments separated by tabs" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "print('a', 'b', 'c')")
      [output | _] = repl.history

      assert output.content =~ "a\tb\tc"
    end

    test "global variables persist across eval calls" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "x = 42")
      assert {:cont, repl} = LuaRepl.eval(repl, "print(x)")

      [output | _] = repl.history
      assert output.content =~ "42"
    end

    test "functions defined in one eval callable in next" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "function add(a, b) return a + b end")
      assert {:halt, answer} = LuaRepl.eval(repl, "return add(2, 3)")

      assert answer == "5"
    end

    test "tables accumulate data across evals" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "results = {}")
      assert {:cont, repl} = LuaRepl.eval(repl, "table.insert(results, 'a')")
      assert {:cont, repl} = LuaRepl.eval(repl, "table.insert(results, 'b')")
      assert {:cont, repl} = LuaRepl.eval(repl, "print(#results)")

      [output | _] = repl.history
      assert output.content =~ "2"
    end

    test "Lua runtime error caught and added to history" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "error('intentional error')")

      [output | _] = repl.history
      assert output.kind == :output
      assert output.content =~ "RuntimeException"
    end

    test "Lua compiler error caught and added to history" do
      repl = create_repl()

      # Invalid Lua syntax
      assert {:cont, repl} = LuaRepl.eval(repl, "if then end")

      [output | _] = repl.history
      assert output.kind == :output
      assert output.content =~ "CompilerException"
    end

    test "Lua state preserved after error - can continue" do
      repl = create_repl()

      # Set a variable
      assert {:cont, repl} = LuaRepl.eval(repl, "x = 100")

      # Cause an error
      assert {:cont, repl} = LuaRepl.eval(repl, "error('oops')")

      # Variable should still be accessible
      assert {:cont, repl} = LuaRepl.eval(repl, "print(x)")
      [output | _] = repl.history
      assert output.content =~ "100"
    end

    test "undefined variable access continues with nil" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "print(undefined_var)")
      [output | _] = repl.history
      assert output.content =~ "nil"
    end
  end

  describe "sandboxing - blocked functions" do
    # Note: The lua library's sandbox makes functions unavailable by causing
    # errors when called, not by setting them to nil. We test that calling
    # these functions results in errors.

    test "io.open raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "io.open('/etc/passwd')")
      [output | _] = repl.history
      # Should produce an error (RuntimeException or similar)
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "os.execute raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "os.execute('ls')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "os.getenv raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "os.getenv('PATH')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "os.exit raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "os.exit(0)")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "os.remove raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "os.remove('/tmp/test')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "require raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "require('os')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "loadstring raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "loadstring('return 1')()")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "loadfile raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "loadfile('/etc/passwd')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "dofile raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "dofile('/etc/passwd')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "debug.debug raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "debug.debug()")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "rawget raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "rawget({}, 'key')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "rawset raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "rawset({}, 'key', 'value')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "getmetatable raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "getmetatable({})")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "setmetatable raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "setmetatable({}, {})")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "collectgarbage raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "collectgarbage('count')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "coroutine.create raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "coroutine.create(function() end)")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end

    test "package.loadlib raises error when called" do
      repl = create_repl()

      assert {:cont, repl} = LuaRepl.eval(repl, "package.loadlib('test', 'init')")
      [output | _] = repl.history
      assert output.content =~ "Exception" or output.content =~ "nil" or output.content =~ "error"
    end
  end

  describe "sandboxing - allowed functions" do
    test "string operations work" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return string.upper('hello')")
      assert answer == "\"HELLO\""
    end

    test "math operations work" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return math.floor(3.7)")
      assert answer == "3"
    end

    test "table operations work" do
      repl = create_repl()

      script = """
      local t = {3, 1, 2}
      table.sort(t)
      return t[1], t[2], t[3]
      """

      assert {:halt, answer} = LuaRepl.eval(repl, script)
      assert answer == "[1, 2, 3]"
    end

    test "os.time works (safe function)" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return type(os.time())")
      assert answer == "\"number\""
    end

    test "os.date works (safe function)" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return type(os.date())")
      assert answer == "\"string\""
    end

    test "tostring works" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return tostring(123)")
      assert answer == "\"123\""
    end

    test "tonumber works" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return tonumber('42')")
      # Lua numbers are floats, so 42 becomes 42.0
      assert answer == "42.0" or answer == "42"
    end

    test "type works" do
      repl = create_repl()

      assert {:halt, answer} = LuaRepl.eval(repl, "return type({})")
      assert answer == "\"table\""
    end

    test "pairs works" do
      repl = create_repl()

      script = """
      local count = 0
      for k, v in pairs({a=1, b=2}) do
        count = count + 1
      end
      return count
      """

      assert {:halt, answer} = LuaRepl.eval(repl, script)
      assert answer == "2"
    end

    test "ipairs works" do
      repl = create_repl()

      script = """
      local sum = 0
      for i, v in ipairs({1, 2, 3}) do
        sum = sum + v
      end
      return sum
      """

      assert {:halt, answer} = LuaRepl.eval(repl, script)
      assert answer == "6"
    end
  end

  describe "rlm.llm_query integration" do
    test "successful call returns (result, nil) tuple" do
      completion_fn = fn _query, _ctx -> {:ok, "completion result"} end
      repl = create_repl_with_completion(completion_fn)

      script = """
      local result, err = rlm.llm_query("test query", "test context")
      print(result)
      print(err)
      """

      assert {:cont, repl} = LuaRepl.eval(repl, script)
      [output | _] = repl.history
      assert output.content =~ "completion result"
      assert output.content =~ "nil"
    end

    test "error returns (nil, error_message) tuple" do
      completion_fn = fn _query, _ctx -> {:error, :some_error} end
      repl = create_repl_with_completion(completion_fn)

      script = """
      local result, err = rlm.llm_query("test query", "test context")
      print(result)
      print(err)
      """

      assert {:cont, repl} = LuaRepl.eval(repl, script)
      [output | _] = repl.history
      lines = String.split(output.content, "\n")
      assert Enum.any?(lines, &(&1 =~ "nil"))
      assert Enum.any?(lines, &(&1 =~ "unexpected error"))
    end

    test "max_depth_reached error returns proper message" do
      completion_fn = fn _query, _ctx -> {:error, :max_depth_reached} end
      repl = create_repl_with_completion(completion_fn)

      script = """
      local result, err = rlm.llm_query("test query", "test context")
      print(err)
      """

      assert {:cont, repl} = LuaRepl.eval(repl, script)
      [output | _] = repl.history
      assert output.content =~ "max recursion depth reached"
    end

    test "max_iterations_reached error returns proper message" do
      completion_fn = fn _query, _ctx -> {:error, :max_iterations_reached} end
      repl = create_repl_with_completion(completion_fn)

      script = """
      local result, err = rlm.llm_query("test query", "test context")
      print(err)
      """

      assert {:cont, repl} = LuaRepl.eval(repl, script)
      [output | _] = repl.history
      assert output.content =~ "max number of iterations reached"
    end

    test "completion function receives correct query and context" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      completion_fn = fn query, ctx ->
        Agent.update(agent, fn calls -> [{query, ctx} | calls] end)
        {:ok, "result"}
      end

      repl = create_repl_with_completion(completion_fn)

      script = """
      rlm.llm_query("my query", "my context")
      """

      assert {:cont, _repl} = LuaRepl.eval(repl, script)

      calls = Agent.get(agent, & &1)
      assert [{"my query", "my context"}] = calls
    end
  end
end
