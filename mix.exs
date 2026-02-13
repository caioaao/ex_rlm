defmodule ExRLM.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_rlm,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:baml_elixir, "~> 1.0.0-pre.24"}
    ]
  end
end
