defmodule ExRLM.Repl.HistoryTest do
  use ExUnit.Case, async: true

  alias ExRLM.Repl.History
  alias ExRLM.Repl.Interaction

  describe inspect(&History.new/0) do
    test "returns empty list" do
      assert History.new() == []
    end
  end

  describe inspect(&History.push/3) do
    test "prepends interaction to history" do
      history = History.new()
      updated = History.push(history, :script, "print('hello')")

      assert [%Interaction{kind: :script, content: "print('hello')"}] = updated
    end

    test "preserves :output kind" do
      history = History.new()
      updated = History.push(history, :output, "hello world")

      assert [%Interaction{kind: :output, content: "hello world"}] = updated
    end

    test "maintains newest-first order" do
      history =
        History.new()
        |> History.push(:script, "first")
        |> History.push(:output, "second")
        |> History.push(:script, "third")

      assert [
               %Interaction{kind: :script, content: "third"},
               %Interaction{kind: :output, content: "second"},
               %Interaction{kind: :script, content: "first"}
             ] = history
    end
  end

  describe inspect(&History.format/1) do
    test "empty history produces valid XML wrapper" do
      result = History.format([])
      assert result == "<repl_history>\n</repl_history>"
    end

    test "scripts wrapped in code tags with lua language" do
      history = [%Interaction{kind: :script, content: "print(1)"}]
      result = History.format(history)

      assert result =~ "<code lang=\"lua\">"
      assert result =~ "</code>"
      assert result =~ "print(1)"
    end

    test "outputs wrapped in output tags" do
      history = [%Interaction{kind: :output, content: "hello world"}]
      result = History.format(history)

      assert result =~ "<output>"
      assert result =~ "</output>"
      assert result =~ "hello world"
    end

    test "content properly indented with 4 spaces" do
      history = [%Interaction{kind: :script, content: "x = 1"}]
      result = History.format(history)

      assert result =~ "    x = 1"
    end

    test "multi-line content indented on each line" do
      history = [%Interaction{kind: :script, content: "x = 1\ny = 2\nz = 3"}]
      result = History.format(history)

      assert result =~ "    x = 1\n"
      assert result =~ "    y = 2\n"
      assert result =~ "    z = 3\n"
    end

    test "history reversed to chronological order" do
      # Push order: first, second, third (newest-first storage)
      # Format order: first, second, third (chronological)
      history =
        History.new()
        |> History.push(:script, "first")
        |> History.push(:output, "second")
        |> History.push(:script, "third")

      result = History.format(history)

      first_pos = :binary.match(result, "first") |> elem(0)
      second_pos = :binary.match(result, "second") |> elem(0)
      third_pos = :binary.match(result, "third") |> elem(0)

      assert first_pos < second_pos
      assert second_pos < third_pos
    end

    test "alternating scripts and outputs formatted correctly" do
      history =
        History.new()
        |> History.push(:script, "print('a')")
        |> History.push(:output, "a\n")
        |> History.push(:script, "print('b')")
        |> History.push(:output, "b\n")

      result = History.format(history)

      assert result =~ "<code lang=\"lua\">"
      assert result =~ "<output>"
      # Count occurrences
      assert length(Regex.scan(~r/<code lang="lua">/, result)) == 2
      assert length(Regex.scan(~r/<output>/, result)) == 2
    end

    test "output truncation at 100,000 chars with ... suffix" do
      long_content = String.duplicate("x", 100_001)
      history = [%Interaction{kind: :output, content: long_content}]
      result = History.format(history)

      # The formatted content should contain truncated output
      assert result =~ "..."
      # Should not contain the full 100,001 x's
      refute result =~ String.duplicate("x", 100_001)
    end

    test "output at exactly 100,000 chars not truncated" do
      exact_content = String.duplicate("x", 100_000)
      history = [%Interaction{kind: :output, content: exact_content}]
      result = History.format(history)

      # Should not have truncation marker
      refute result =~ "..."
      # Should contain all x's (within the output tags)
      assert result =~ exact_content
    end

    test "scripts are not truncated even if long" do
      long_script = String.duplicate("x", 100_001)
      history = [%Interaction{kind: :script, content: long_script}]
      result = History.format(history)

      # Scripts should not be truncated
      assert result =~ long_script
      refute result =~ "..."
    end
  end
end
