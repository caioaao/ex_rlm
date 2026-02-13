defmodule ExRLM.Repl.ParserTest do
  use ExUnit.Case, async: true

  alias ExRLM.Repl.Parser

  describe "parse_response/1" do
    test "returns {:final_text, text} when FINAL() is found outside code blocks" do
      response = """
      I've analyzed the data and found the answer.

      FINAL(The answer is 42)
      """

      assert {:final_text, "The answer is 42"} = Parser.parse_response(response)
    end

    test "returns {:final_var, var} when FINAL_VAR() is found outside code blocks" do
      response = """
      I've stored the result in a variable.

      FINAL_VAR(result)
      """

      assert {:final_var, "result"} = Parser.parse_response(response)
    end

    test "returns {:code_blocks, blocks, text} when code blocks are found without FINAL" do
      response = """
      Let me compute that.

      ```repl
      x = 1 + 1
      ```

      And another calculation:

      ```repl
      y = x * 2
      ```
      """

      assert {:code_blocks, blocks, _remaining} = Parser.parse_response(response)
      assert length(blocks) == 2
      assert Enum.at(blocks, 0) =~ "x = 1 + 1"
      assert Enum.at(blocks, 1) =~ "y = x * 2"
    end

    test "returns {:continue, text} when no code blocks or FINAL markers" do
      response = "I need to think about this more."

      assert {:continue, ^response} = Parser.parse_response(response)
    end

    test "ignores FINAL() inside code blocks" do
      response = """
      Here's an example of using FINAL:

      ```repl
      -- This is just a comment showing FINAL(example)
      print("hello")
      ```

      Let me continue working.
      """

      assert {:code_blocks, blocks, _remaining} = Parser.parse_response(response)
      assert length(blocks) == 1
    end

    test "ignores FINAL_VAR() inside code blocks" do
      response = """
      Here's the code:

      ```repl
      -- FINAL_VAR(test) is shown here as example
      x = 10
      ```

      Still working on it.
      """

      assert {:code_blocks, blocks, _remaining} = Parser.parse_response(response)
      assert length(blocks) == 1
    end

    test "detects FINAL() after code blocks" do
      response = """
      Let me run this:

      ```repl
      result = 42
      ```

      FINAL(The result is 42)
      """

      assert {:final_text, "The result is 42"} = Parser.parse_response(response)
    end

    test "FINAL_VAR takes precedence when both are outside code blocks" do
      response = """
      FINAL_VAR(answer)
      FINAL(This should be ignored)
      """

      assert {:final_var, "answer"} = Parser.parse_response(response)
    end

    test "handles multiline FINAL content" do
      response = """
      FINAL(This is a
      multiline
      answer)
      """

      assert {:final_text, text} = Parser.parse_response(response)
      assert text =~ "multiline"
    end

    test "trims whitespace from FINAL text" do
      response = "FINAL(  trimmed answer  )"

      assert {:final_text, "trimmed answer"} = Parser.parse_response(response)
    end
  end

  describe "extract_code_blocks/1" do
    test "extracts single code block" do
      response = """
      ```repl
      x = 1
      ```
      """

      blocks = Parser.extract_code_blocks(response)
      assert length(blocks) == 1
      assert hd(blocks) =~ "x = 1"
    end

    test "extracts multiple code blocks" do
      response = """
      ```repl
      a = 1
      ```

      Some text

      ```repl
      b = 2
      ```
      """

      blocks = Parser.extract_code_blocks(response)
      assert length(blocks) == 2
    end

    test "returns empty list when no code blocks" do
      response = "Just some text without code"

      assert [] = Parser.extract_code_blocks(response)
    end

    test "ignores non-repl code blocks" do
      response = """
      ```lua
      -- This should be ignored
      ```

      ```repl
      -- This should be extracted
      ```

      ```python
      # Also ignored
      ```
      """

      blocks = Parser.extract_code_blocks(response)
      assert length(blocks) == 1
      assert hd(blocks) =~ "This should be extracted"
    end
  end
end
