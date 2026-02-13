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
