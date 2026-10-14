defmodule AtmlPdf.TextWrap do
  @moduledoc """
  Splits text into lines using the width estimate shared by layout and rendering.
  """

  @doc """
  Wraps text to an estimated width in points, preserving explicit line breaks.

  Long words are split at grapheme boundaries when they exceed the width.
  Spaces and tabs are retained, including when a line break falls within them.
  A non-positive font size preserves explicit newlines without width wrapping.

  ## Examples

      iex> AtmlPdf.TextWrap.lines("abcdefgh", 15, 10)
      ["abc", "def", "gh"]

      iex> AtmlPdf.TextWrap.lines("one\\ntwo", 100, 10)
      ["one", "two"]

  """
  @spec lines(String.t(), number(), number()) :: [String.t()]
  def lines(text, _width, font_size) when is_binary(text) and font_size <= 0 do
    String.split(text, "\n")
  end

  def lines(text, width, font_size) when is_binary(text) and is_number(width) and font_size > 0 do
    max_chars = max(1, trunc(width / (font_size * 0.5)))

    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line(&1, max_chars))
  end

  defp wrap_line(line, max_chars) do
    tokens = ~r/[ \t]+|[^ \t]+/u |> Regex.scan(line) |> List.flatten()

    case tokens do
      [] -> [""]
      _ -> wrap_tokens(tokens, max_chars, "", [])
    end
  end

  defp wrap_tokens([], _max_chars, "", lines), do: Enum.reverse(lines)
  defp wrap_tokens([], _max_chars, current, lines), do: Enum.reverse([current | lines])

  defp wrap_tokens([token | rest], max_chars, current, lines) do
    candidate = current <> token

    cond do
      String.length(candidate) <= max_chars ->
        wrap_tokens(rest, max_chars, candidate, lines)

      current != "" ->
        wrap_tokens([token | rest], max_chars, "", [current | lines])

      true ->
        {part, remainder} = String.split_at(token, max_chars)

        wrap_tokens(if(remainder == "", do: rest, else: [remainder | rest]), max_chars, "", [
          part | lines
        ])
    end
  end
end
