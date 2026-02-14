defmodule ExRLM.Completion.Prompts.ReplCompletion do
  @moduledoc false
  require EEx

  alias ExRLM.LLM.Message

  @external_resource "priv/templates/repl_completion_system.eex"
  @external_resource "priv/templates/repl_completion_user.eex"

  EEx.function_from_file(:defp, :system_template, "priv/templates/repl_completion_system.eex", [
    :assigns
  ])

  EEx.function_from_file(:defp, :user_template, "priv/templates/repl_completion_user.eex", [
    :assigns
  ])

  @spec build_messages(%{query: String.t(), repl_history: String.t(), remaining: pos_integer()}) ::
          [Message.t()]
  def build_messages(%{query: query, repl_history: repl_history, remaining: remaining}) do
    assigns = [query: query, repl_history: repl_history, remaining: remaining]

    [
      %Message{role: "system", content: system_template(assigns)},
      %Message{role: "user", content: user_template(assigns)}
    ]
  end
end
