defmodule ExRLM.Repl do
  @moduledoc """
  Responsible for instantiating the Lua engine, setting up the context, and querying the LLM.
  """

  defstruct [:lua_state, :model, :recursive_model]

  @type t :: %__MODULE__{
          lua_state: term(),
          model: String.t(),
          recursive_model: String.t()
        }

  @doc """
  Creates a new Repl instance with the given options.

  ## Options
    * `:model` - The primary model to use for completions
    * `:recursive_model` - The model to use for recursive calls
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    lua_state = Lua.new()

    %__MODULE__{
      lua_state: lua_state,
      model: Keyword.fetch!(opts, :model),
      recursive_model: Keyword.get(opts, :recursive_model, Keyword.fetch!(opts, :model))
    }
  end

  @doc """
  Runs a completion query through the LLM with Lua execution.

  ## Options
    * `:context` - Additional context for the query
    * `:max_iterations` - Maximum number of iterations (default: 10)
    * `:max_depth` - Maximum depth of recursion (default: 10)
  """
  @spec completion(t(), String.t(), keyword()) :: {:ok, {t(), String.t()}} | {:error, term()}
  def completion(repl, _query, opts) do
    _context = Keyword.get(opts, :context)
    # TODO: Implement the RLM loop
    {:ok, {repl, "Not implemented yet"}}
  end
end
