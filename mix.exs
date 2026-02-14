defmodule ExRLM.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_rlm,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "ExRLM",
      source_url: "https://github.com/caioaao/ex-rlm",
      homepage_url: "https://github.com/caioaao/ex-rlm",
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "tutorials/getting-started.md",
        "guides/custom-llm-providers.md",
        "explanation/how-rlm-works.md"
      ],
      groups_for_modules: [
        "Public API": [ExRLM, ExRLM.LLM],
        "LLM Providers": [ExRLM.Completion.OpenAI]
      ],
      groups_for_extras: [
        Tutorials: ["tutorials/getting-started.md"],
        Guides: ["guides/custom-llm-providers.md"],
        Explanation: ["explanation/how-rlm-works.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:lua, "~> 0.4"},
      {:tesla, "~> 1.13"},
      {:mint, "~> 1.6"},
      {:jason, "~> 1.4"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]
end
