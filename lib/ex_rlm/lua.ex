defmodule ExRLM.Lua do
  @moduledoc """
  Initializes the Lua VM with ExRLM APIs registered.

  The Lua environment is sandboxed to prevent LLM-generated code from
  accessing dangerous functions. In addition to the library defaults
  (io, file, os.execute, package, load, etc.), we also block:

  - `debug` - Introspection that could escape sandbox
  - `rawget/rawset` - Bypass metamethod protections
  - `getmetatable/setmetatable` - Modify object behavior
  - `collectgarbage` - Resource manipulation
  - `coroutine` - Not needed for RLM use case
  """

  # Library defaults that we must include (since passing sandboxed: replaces, not extends)
  @library_default_sandbox [
    [:io],
    [:file],
    [:os, :execute],
    [:os, :exit],
    [:os, :getenv],
    [:os, :remove],
    [:os, :rename],
    [:os, :tmpname],
    [:package],
    [:load],
    [:loadfile],
    [:require],
    [:dofile],
    [:loadstring]
  ]

  # Additional sandbox items beyond library defaults
  @additional_sandbox [
    [:debug],
    [:rawget],
    [:rawset],
    [:getmetatable],
    [:setmetatable],
    [:collectgarbage],
    [:coroutine]
  ]

  @sandbox @library_default_sandbox ++ @additional_sandbox

  @doc """
  Creates a new Lua state with the completion API registered.

  ## Options
    * `:model` - Model name for recursive calls (required)
    * `:max_iterations` - Max iterations, preserved across recursion (default: 10)
    * `:max_depth` - Initial recursion depth limit (default: 10)
    * `:completion_fn` - Function to call for completions (optional, defaults to stub)

  The completion function signature is `(query, context, config) -> result`.
  """
  @spec new(keyword()) :: Lua.t()
  def new(opts \\ []) do
    config = %{
      model: Keyword.fetch!(opts, :model),
      max_iterations: Keyword.get(opts, :max_iterations, 10),
      max_depth: Keyword.get(opts, :max_depth, 10),
      completion_fn: Keyword.get(opts, :completion_fn, &default_completion/3)
    }

    Lua.new(sandboxed: @sandbox)
    |> Lua.load_api(ExRLM.Lua.Completion)
    |> Lua.put_private(:rlm_config, config)
  end

  defp default_completion(_query, _context, _config) do
    # Stub - will be replaced by BAML integration
    "TODO: LLM completion not implemented"
  end
end
