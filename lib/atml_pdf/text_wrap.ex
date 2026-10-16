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
    lines(text, width, font_size, fn segment -> String.length(segment) * font_size * 0.5 end)
  end

  @doc """
  Wraps text using a supplied function that measures a string in points.

  ## Examples

      iex> AtmlPdf.TextWrap.lines("WWWW", 20, 10, fn text -> String.length(text) * 8 end)
      ["WW", "WW"]

  """
  @spec lines(String.t(), number(), number(), (String.t() -> number())) :: [String.t()]
  def lines(text, _width, font_size, _measure) when is_binary(text) and font_size <= 0 do
    String.split(text, "\n")
  end

  def lines(text, width, font_size, measure)
      when is_binary(text) and is_number(width) and font_size > 0 and is_function(measure, 1) do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line(&1, width, measure))
  end

  @doc """
  Measures text using ExGuten's standard-font metrics when available.

  Other fonts use the character-width estimate until their metrics can be
  shared with layout.

  ## Examples

      iex> AtmlPdf.TextWrap.width("Helvetica-Bold", 10, "WW") > 10
      true

  """
  @spec width(String.t() | nil, number(), String.t()) :: float()
  def width(font_name, font_size, text) when is_binary(text) do
    if is_binary(font_name) and ExGuten.Font.standard_font?(font_name) and
         Enum.all?(String.to_charlist(text), &(&1 <= 255)) do
      ExGuten.Font.text_width(font_name, font_size, text)
    else
      String.length(text) * font_size * 0.5
    end
  end

  @doc """
  Returns the standard font name used to measure an ATML font setting.

  Returns `nil` for fonts without ExGuten standard-font metrics.

  ## Examples

      iex> AtmlPdf.TextWrap.metric_font_name("Helvetica", :bold)
      "Helvetica-Bold"

  """
  @spec metric_font_name(String.t(), :normal | :bold) :: String.t() | nil
  def metric_font_name(family, weight) do
    case {String.downcase(family), weight} do
      {"helvetica", :bold} -> "Helvetica-Bold"
      {"helvetica", _} -> "Helvetica"
      {"times", :bold} -> "Times-Bold"
      {"times", _} -> "Times-Roman"
      {"times-roman", :bold} -> "Times-Bold"
      {"times-roman", _} -> "Times-Roman"
      {"courier", :bold} -> "Courier-Bold"
      {"courier", _} -> "Courier"
      _ -> nil
    end
  end

  defp wrap_line(line, width, measure) do
    tokens = ~r/[ \t]+|[^ \t]+/u |> Regex.scan(line) |> List.flatten()

    case tokens do
      [] -> [""]
      _ -> wrap_tokens(tokens, width, measure, "", [])
    end
  end

  defp wrap_tokens([], _width, _measure, "", lines), do: Enum.reverse(lines)
  defp wrap_tokens([], _width, _measure, current, lines), do: Enum.reverse([current | lines])

  defp wrap_tokens([token | rest], width, measure, current, lines) do
    candidate = current <> token

    cond do
      measure.(candidate) <= width ->
        wrap_tokens(rest, width, measure, candidate, lines)

      current != "" ->
        wrap_tokens([token | rest], width, measure, "", [current | lines])

      true ->
        {part, remainder} = split_to_width(String.graphemes(token), width, measure, "")

        wrap_tokens(if(remainder == "", do: rest, else: [remainder | rest]), width, measure, "", [
          part | lines
        ])
    end
  end

  defp split_to_width([], _width, _measure, part), do: {part, ""}

  defp split_to_width([grapheme | rest], width, measure, part) do
    candidate = part <> grapheme

    if part == "" or measure.(candidate) <= width do
      split_to_width(rest, width, measure, candidate)
    else
      {part, Enum.join([grapheme | rest])}
    end
  end
end
