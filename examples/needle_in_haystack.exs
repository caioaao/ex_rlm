defmodule NeedleInHaystack do
  @random_words ~w(blah random text data content information sample)

  def generate_massive_context(num_lines \\ 1_000_000, answer) do
    IO.puts("Generating massive context with #{num_lines} lines...")

    lines =
      for _ <- 1..num_lines do
        num_words = Enum.random(3..8)

        1..num_words
        |> Enum.map(fn _ -> Enum.random(@random_words) end)
        |> Enum.join(" ")
      end

    # Insert the magic number at a random position (somewhere in the middle)
    magic_position = Enum.random(400_000..600_000)
    lines = List.replace_at(lines, magic_position, "The magic number is #{answer}")

    IO.puts("Magic number inserted at position #{magic_position}")

    Enum.join(lines, "\n")
  end

  def main do
    IO.puts("Example of using ExRLM on a needle-in-haystack problem.")

    answer = Enum.random(1_000_000..9_999_999) |> to_string()
    context = generate_massive_context(1_000_000, answer)

    query = "I'm looking for a magic number. What is it?"

    llm = ExRLM.Completion.OpenAI.new("gpt-4o-mini")
    case ExRLM.completion(query, llm: llm, context: context) do
      {:ok,  result} ->
        IO.puts("Result: #{result}. Expected: #{answer}")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}. Expected: #{answer}")
    end
  end
end

NeedleInHaystack.main()
