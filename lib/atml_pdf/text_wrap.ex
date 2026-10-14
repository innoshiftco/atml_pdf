defmodule AtmlPdf.TextWrap do
  @moduledoc """
  Splits text into lines using the width estimate shared by layout and rendering.
  """

  @doc """
  Wraps text to an estimated width in points, preserving explicit line breaks.

  Long words are split at grapheme boundaries when they exceed the width.

  ## Examples

      iex> AtmlPdf.TextWrap.lines("abcdefgh", 15, 10)
      ["abc", "def", "gh"]

      iex> AtmlPdf.TextWrap.lines("one\\ntwo", 100, 10)
      ["one", "two"]

  """
  @spec lines(String.t(), number(), number()) :: [String.t()]
  def lines(text, width, font_size) when is_binary(text) and is_number(width) and font_size > 0 do
    max_chars = max(1, trunc(width / (font_size * 0.5)))

    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line(&1, max_chars))
  end

  defp wrap_line(line, max_chars) do
    words = String.split(line, ~r/[ \t]+/, trim: true)

    case words do
      [] -> [""]
      _ -> wrap_words(words, max_chars, "", [])
    end
  end

  defp wrap_words([], _max_chars, "", lines), do: Enum.reverse(lines)
  defp wrap_words([], _max_chars, current, lines), do: Enum.reverse([current | lines])

  defp wrap_words([word | rest], max_chars, current, lines) do
    candidate = if current == "", do: word, else: current <> " " <> word

    cond do
      String.length(candidate) <= max_chars ->
        wrap_words(rest, max_chars, candidate, lines)

      current != "" ->
        wrap_words([word | rest], max_chars, "", [current | lines])

      true ->
        {part, remainder} = String.split_at(word, max_chars)

        wrap_words(if(remainder == "", do: rest, else: [remainder | rest]), max_chars, "", [
          part | lines
        ])
    end
  end
end
