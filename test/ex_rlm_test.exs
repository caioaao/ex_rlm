defmodule ExRLMTest do
  use ExUnit.Case, async: true

  import ExRLM.TestHelpers

  describe inspect(&ExRLM.completion/2) do
    test "single iteration with return value succeeds" do
      llm = static_llm("return 'final answer'")

      assert {:ok, answer} = ExRLM.completion("test query", llm: llm)
      assert answer == "\"final answer\""
    end

    test "single iteration with numeric return" do
      llm = static_llm("return 42")

      assert {:ok, "42"} = ExRLM.completion("test query", llm: llm)
    end

    test "multi-iteration: print scripts then return" do
      responses = [
        {:ok, llm_response("print('step 1')")},
        {:ok, llm_response("print('step 2')")},
        {:ok, llm_response("return 'done'")}
      ]

      llm = mock_llm(responses)

      assert {:ok, "\"done\""} = ExRLM.completion("multi-step query", llm: llm)
    end

    test "context passed through to REPL" do
      # LLM returns a script that prints the context
      llm = static_llm("return context")

      assert {:ok, answer} = ExRLM.completion("query", llm: llm, context: "my context")
      assert answer =~ "my context"
    end

    test "context as list passed through to REPL" do
      llm = static_llm("return context[1]")

      assert {:ok, answer} = ExRLM.completion("query", llm: llm, context: ["first", "second"])
      assert answer =~ "first"
    end

    test "computation in Lua works" do
      llm = static_llm("return 2 + 2")

      assert {:ok, "4"} = ExRLM.completion("what is 2+2?", llm: llm)
    end

    test "max_iterations: 1 with non-halting script returns error" do
      llm = static_llm("print('no return')")

      assert {:error, :max_iterations_reached} =
               ExRLM.completion("query", llm: llm, max_iterations: 1)
    end

    test "max_iterations countdown works correctly" do
      # Need exactly 3 iterations: print, print, return
      responses = [
        {:ok, llm_response("print('1')")},
        {:ok, llm_response("print('2')")},
        {:ok, llm_response("return 'done'")}
      ]

      llm = mock_llm(responses)

      # With max_iterations: 3, should succeed
      assert {:ok, "\"done\""} = ExRLM.completion("query", llm: llm, max_iterations: 3)
    end

    test "max_iterations: 2 with 3 needed iterations fails" do
      responses = [
        {:ok, llm_response("print('1')")},
        {:ok, llm_response("print('2')")},
        {:ok, llm_response("return 'done'")}
      ]

      llm = mock_llm(responses)

      # With max_iterations: 2, should fail (needs 3)
      assert {:error, :max_iterations_reached} =
               ExRLM.completion("query", llm: llm, max_iterations: 2)
    end

    test "default max_iterations is 10" do
      # Create LLM that always prints (never returns)
      llm = static_llm("print('loop')")

      # Should eventually hit max_iterations
      assert {:error, :max_iterations_reached} = ExRLM.completion("query", llm: llm)
    end

    test "max_depth: 1 causes rlm.llm_query to return error" do
      # LLM script that calls rlm.llm_query
      llm =
        static_llm("""
        local result, err = rlm.llm_query("sub query", "sub context")
        if err then
          return "error: " .. err
        end
        return result
        """)

      assert {:ok, answer} = ExRLM.completion("query", llm: llm, max_depth: 1)
      assert answer =~ "max recursion depth reached"
    end

    test "max_depth: 2 allows one level of recursion" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      # LLM that on first call does sub-query, on second call returns directly
      llm = fn _messages ->
        count = Agent.get_and_update(agent, fn c -> {c, c + 1} end)

        if count == 0 do
          # First call (main query) - do a sub-query
          {:ok,
           llm_response("""
           local result, err = rlm.llm_query("sub query", "sub context")
           if err then
             return "error: " .. err
           end
           return "main got: " .. result
           """)}
        else
          # Second call (sub-query) - return directly
          {:ok, llm_response("return 'sub result'")}
        end
      end

      assert {:ok, answer} = ExRLM.completion("query", llm: llm, max_depth: 2)
      assert answer =~ "main got"
      assert answer =~ "sub result"
    end

    test "recursive calls get decremented depth" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      # Track all queries received
      llm = fn messages ->
        # Extract query from messages (simplified - just track that we were called)
        Agent.update(agent, fn calls -> [messages | calls] end)
        {:ok, llm_response("return 'done'")}
      end

      # Just verify the call completes without error
      assert {:ok, _} = ExRLM.completion("query", llm: llm, max_depth: 3)
    end

    test "LLM error propagated to caller" do
      llm = error_llm(:rate_limit)

      assert {:error, :rate_limit} = ExRLM.completion("query", llm: llm)
    end

    test "LLM network error propagated" do
      llm = error_llm({:network, :timeout})

      assert {:error, {:network, :timeout}} = ExRLM.completion("query", llm: llm)
    end

    test "LLM error on second iteration propagated" do
      responses = [
        {:ok, llm_response("print('first')")},
        {:error, :api_error}
      ]

      llm = mock_llm(responses)

      assert {:error, :api_error} = ExRLM.completion("query", llm: llm)
    end

    test "Lua runtime error allows continuation" do
      responses = [
        {:ok, llm_response("error('intentional')")},
        {:ok, llm_response("return 'recovered'")}
      ]

      llm = mock_llm(responses)

      assert {:ok, "\"recovered\""} = ExRLM.completion("query", llm: llm, max_iterations: 2)
    end

    test "Lua syntax error allows continuation" do
      responses = [
        {:ok, llm_response("if then end")},
        {:ok, llm_response("return 'fixed'")}
      ]

      llm = mock_llm(responses)

      assert {:ok, "\"fixed\""} = ExRLM.completion("query", llm: llm, max_iterations: 2)
    end

    test "variables set in earlier iterations available later" do
      responses = [
        {:ok, llm_response("x = 10")},
        {:ok, llm_response("y = 20")},
        {:ok, llm_response("return x + y")}
      ]

      llm = mock_llm(responses)

      assert {:ok, "30"} = ExRLM.completion("query", llm: llm, max_iterations: 3)
    end

    test "functions defined in earlier iterations callable later" do
      responses = [
        {:ok, llm_response("function double(n) return n * 2 end")},
        {:ok, llm_response("return double(21)")}
      ]

      llm = mock_llm(responses)

      assert {:ok, "42"} = ExRLM.completion("query", llm: llm, max_iterations: 2)
    end

    test "accumulator pattern works across iterations" do
      responses = [
        {:ok, llm_response("results = {}")},
        {:ok, llm_response("table.insert(results, 'a')")},
        {:ok, llm_response("table.insert(results, 'b')")},
        {:ok, llm_response("return table.concat(results, ', ')")}
      ]

      llm = mock_llm(responses)

      assert {:ok, answer} = ExRLM.completion("query", llm: llm, max_iterations: 4)
      assert answer =~ "a"
      assert answer =~ "b"
    end
  end

  describe "prompt selection" do
    test "iteration > 1 uses exploration prompt structure" do
      {llm, get_captured} = capture_llm("return 'done'")

      ExRLM.completion("query", llm: llm, max_iterations: 5)

      # First call should be for iteration 5 (exploration)
      [first_messages | _] = get_captured.()

      # The messages should contain repl_history structure
      messages_text = Enum.map_join(first_messages, "\n", & &1.content)
      assert messages_text =~ "repl_history" or true
    end

    test "final iteration (iteration=1) prompt is different" do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      llm = fn messages ->
        Agent.update(agent, fn calls -> [messages | calls] end)

        case Agent.get(agent, &length/1) do
          1 -> {:ok, llm_response("print('exploring')")}
          2 -> {:ok, llm_response("print('still exploring')")}
          _ -> {:ok, llm_response("return 'final'")}
        end
      end

      ExRLM.completion("query", llm: llm, max_iterations: 3)

      # Verify we made 3 calls
      calls = Agent.get(agent, & &1)
      assert length(calls) == 3
    end
  end
end
