defmodule ExRLM.Repl.Parser do
  @moduledoc """
  Parses LLM responses to extract Lua code blocks and FINAL markers.
  """

  @type parse_result ::
          {:final_text, String.t()}
          | {:final_var, String.t()}
          | {:code_blocks, [String.t()], String.t()}
          | {:continue, String.t()}

  @code_block_regex ~r/```repl\n(.*?)```/s
  @final_text_regex ~r/FINAL\((.*)\)/s
  @final_var_regex ~r/FINAL_VAR\((\w+)\)/

  @doc """
  Parses an LLM response to extract code blocks and FINAL markers.

  Returns one of:
  - `{:final_text, text}` - Direct text answer found
  - `{:final_var, variable_name}` - Variable reference to resolve from Lua state
  - `{:code_blocks, blocks, remaining_text}` - Lua code blocks to execute
  - `{:continue, text}` - No code blocks or FINAL markers found
  """
  @spec parse_response(String.t()) :: parse_result
  def parse_response(response) do
    # Find all code block positions to exclude them from FINAL detection
    code_blocks = extract_code_blocks(response)
    code_block_ranges = find_code_block_ranges(response)

    # Check for FINAL markers outside code blocks
    case find_final_outside_code_blocks(response, code_block_ranges) do
      {:final_text, text} ->
        {:final_text, text}

      {:final_var, var} ->
        {:final_var, var}

      nil ->
        if code_blocks == [] do
          {:continue, response}
        else
          remaining_text = remove_code_blocks(response)
          {:code_blocks, code_blocks, remaining_text}
        end
    end
  end

  @doc """
  Extracts all ```repl code blocks from the response.
  """
  @spec extract_code_blocks(String.t()) :: [String.t()]
  def extract_code_blocks(response) do
    @code_block_regex
    |> Regex.scan(response, capture: :all_but_first)
    |> List.flatten()
  end

  # Returns list of {start, end} tuples for code block positions
  defp find_code_block_ranges(response) do
    @code_block_regex
    |> Regex.scan(response, return: :index)
    |> Enum.map(fn [{start, length} | _] -> {start, start + length} end)
  end

  # Finds FINAL or FINAL_VAR markers that are not inside code blocks
  defp find_final_outside_code_blocks(response, code_block_ranges) do
    # Check for FINAL_VAR first (more specific)
    case Regex.run(@final_var_regex, response, return: :index) do
      [{match_start, _} | _] ->
        if outside_code_blocks?(match_start, code_block_ranges) do
          [[_, var]] = Regex.scan(@final_var_regex, response, capture: :all)
          {:final_var, var}
        else
          check_final_text(response, code_block_ranges)
        end

      nil ->
        check_final_text(response, code_block_ranges)
    end
  end

  defp check_final_text(response, code_block_ranges) do
    case Regex.run(@final_text_regex, response, return: :index) do
      [{match_start, _} | _] ->
        if outside_code_blocks?(match_start, code_block_ranges) do
          [[_, text]] = Regex.scan(@final_text_regex, response, capture: :all)
          {:final_text, String.trim(text)}
        else
          nil
        end

      nil ->
        nil
    end
  end

  defp outside_code_blocks?(position, code_block_ranges) do
    not Enum.any?(code_block_ranges, fn {block_start, block_end} ->
      position >= block_start and position < block_end
    end)
  end

  defp remove_code_blocks(response) do
    Regex.replace(@code_block_regex, response, "")
    |> String.trim()
  end
end
