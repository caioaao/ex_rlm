defmodule ExRLM.LuaRepl do
  alias ExRLM.Repl

  defstruct [:lua, :history]

  @type t() :: %__MODULE__{
          lua: Lua.t(),
          history: list(Repl.Interaction.t())
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
        repl = update_in(repl.history, &Repl.History.push(&1, :output, Exception.message(e)))
        {:cont, repl}
    end
  end
end
