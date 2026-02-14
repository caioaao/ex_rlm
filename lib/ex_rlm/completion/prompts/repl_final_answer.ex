defmodule ExRLM.Completion.Prompts.ReplFinalAnswer do
  @moduledoc """
  Generates message list for REPL final answer prompts (last iteration).
  """
  require EEx

  alias ExRLM.LLM.Message

  @external_resource "priv/templates/repl_final_answer_system.eex"
  @external_resource "priv/templates/repl_final_answer_user.eex"

  EEx.function_from_file(
    :defp,
    :system_template,
    "priv/templates/repl_final_answer_system.eex",
    [:assigns]
  )

  EEx.function_from_file(:defp, :user_template, "priv/templates/repl_final_answer_user.eex", [
    :assigns
  ])

  @spec build_messages(%{query: String.t(), repl_history: String.t()}) ::
          [Message.t()]
  def build_messages(%{query: query, repl_history: repl_history}) do
    assigns = [query: query, repl_history: repl_history]

    [
      %Message{role: "system", content: system_template(assigns)},
      %Message{role: "user", content: user_template(assigns)}
    ]
  end
end
