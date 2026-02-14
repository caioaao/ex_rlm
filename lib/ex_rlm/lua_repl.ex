defmodule ExRLM.LuaRepl do
  @moduledoc """
  Lua REPL environment for RLM execution.

  This module provides a sandboxed Lua environment where the LLM can execute code
  to analyze context. The environment runs on [Luerl](https://github.com/rvirding/luerl),
  an Erlang implementation of Lua.

  ## Sandbox Security

  The following are **blocked** for security:

  | Category | Blocked Functions |
  |----------|-------------------|
  | File I/O | `io`, `file` |
  | System access | `os.execute`, `os.exit`, `os.getenv`, `os.remove`, `os.rename`, `os.tmpname` |
  | Code loading | `require`, `dofile`, `load`, `loadfile`, `loadstring`, `package` |
  | Debug/introspection | `debug`, `rawget`, `rawset`, `getmetatable`, `setmetatable` |
  | Memory | `collectgarbage` |
  | Coroutines | `coroutine` |

  ## Available Functions

  The LLM has access to standard Lua operations:

  ### String Operations
      #context                          -- size in bytes
      string.sub(s, start, end_pos)     -- substring (1-indexed, end inclusive)
      string.find(s, pattern)           -- returns start_pos, end_pos or nil
      string.find(s, pattern, init)     -- search from position
      string.match(s, pattern)          -- returns captured text or nil
      string.lower(s) / string.upper(s) -- case conversion
      string.gsub(s, pattern, repl)     -- replace (string replacement only!)

  ### Math Operations
      math.min(), math.max()
      math.floor(), math.ceil()
      math.abs(), math.sqrt()

  ### Table Operations
      table.insert(t, v)
      table.concat(t, sep)
      #table  -- length

  ### Other
      tonumber(s), tostring(n), type(v)
      pairs(t), ipairs(t)
      os.time(), os.date()

  ## Luerl Limitations

  Luerl has a restricted stdlib compared to standard Lua:

  - `string.gmatch()` and `string.gfind()` **do not exist** - use `string.find()` in a loop
  - `string.gsub()` only works with **string replacements**, not replacement functions
  - For pattern-based splitting, use `string.find()` + `string.sub()` in a loop

  ## Error Recovery

  Lua runtime and compiler errors are captured and added to the REPL history
  instead of crashing. This allows the LLM to see its mistakes and correct
  them in subsequent iterations.
  """

  alias ExRLM.Repl

  defstruct [:lua, :history]

  @typedoc "Internal REPL state. Users should not access fields directly."
  @opaque t() :: %__MODULE__{
            lua: Lua.t(),
            history: list()
          }

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

  @typep completion_fn() :: (query :: String.t(), context :: String.t() ->
                               {:ok, String.t()} | {:error, term()})

  @spec new(completion_fn :: completion_fn(), context :: list(String.t())) :: t()
  def new(completion_fn, context) do
    lua =
      Lua.new(sandboxed: @sandbox)
      |> Lua.load_api(ExRLM.Lua.Completion)
      |> Lua.set!([:print], &capture_print/2)
      |> Lua.put_private(:completion_fn, completion_fn)
      |> Lua.put_private(:output_buffer, [])
      |> Lua.set!([:context], context)

    %__MODULE__{history: Repl.History.new(), lua: lua}
  end

  defp capture_print(args, %Lua{} = lua) do
    {:ok, buffer} = Lua.get_private(lua, :output_buffer)

    {strings, lua} =
      Enum.map_reduce(args, lua, fn arg, lua -> Lua.call_function!(lua, [:tostring], [arg]) end)

    output = [Enum.intersperse(strings, "\t"), "\n"]
    lua = Lua.put_private(lua, :output_buffer, [output | buffer])
    {[], lua}
  end

  @spec eval(t(), String.t()) ::
          {:halt, answer :: String.t()}
          | {:cont, t()}
          | {:error, term()}
  def eval(repl, script) do
    repl = update_in(repl.history, &Repl.History.push(&1, :script, script))

    # Clear output buffer before eval
    lua = Lua.put_private(repl.lua, :output_buffer, [])

    try do
      case Lua.eval!(lua, script, decode: false) do
        {[], lua} ->
          # No return value - use captured output
          {:ok, buffer} = Lua.get_private(lua, :output_buffer)
          output = buffer |> Enum.reverse() |> IO.iodata_to_binary()

          repl = put_in(repl.lua, lua)
          repl = update_in(repl.history, &Repl.History.push(&1, :output, output))

          {:cont, repl}

        {[answer], _lua} ->
          # Single return value - final answer
          {:halt, inspect(answer)}

        {answers, _lua} ->
          # Multiple return values - final answer
          {:halt, inspect(answers)}
      end
    rescue
      e in [Lua.RuntimeException, Lua.CompilerException] ->
        # Instead of throwing the error, we simply add it to the Lua history,
        # and we also maintain the Lua state so the execution can continue.
        # This allows for the LLM to see the error but continue iterating.
        repl = update_in(repl.history, &Repl.History.push(&1, :output, inspect(e)))
        {:cont, repl}
    end
  end
end
