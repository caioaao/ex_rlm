defmodule ExRLM.LLM do
  @moduledoc """
  BAML client for LLM API calls.
  """

  use BamlElixir.Client, path: {:ex_rlm, "priv/baml_src"}
end
