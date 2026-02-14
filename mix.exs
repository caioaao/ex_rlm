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
      docs: docs(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"},
        plt_add_apps: [:mix],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "doc/tutorials/getting-started.md",
        "doc/guides/custom-llm-providers.md",
        "doc/explanation/how-rlm-works.md"
      ],
      groups_for_modules: [
        "Public API": [ExRLM, ExRLM.LLM],
        Types: [ExRLM.LLM.Message, ExRLM.LLM.Response, ExRLM.LLM.Usage],
        "LLM Providers": [ExRLM.Completion.OpenAI]
      ],
      groups_for_extras: [
        Tutorials: ["doc/tutorials/getting-started.md"],
        Guides: ["doc/guides/custom-llm-providers.md"],
        Explanation: ["doc/explanation/how-rlm-works.md"]
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
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]
end
