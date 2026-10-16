defmodule AtmlPdf.TextWrapTest do
  use ExUnit.Case, async: true

  alias AtmlPdf.TextWrap

  doctest TextWrap

  describe "lines/3" do
    test "splits a word without spaces into lines that fit" do
      assert TextWrap.lines("abcdefgh", 15, 10) == ["abc", "def", "gh"]
    end

    test "handles widths smaller than one character" do
      assert TextWrap.lines("abc", 0, 10) == ["a", "b", "c"]
    end

    test "preserves explicit blank lines" do
      assert TextWrap.lines("one\n\ntwo", 100, 10) == ["one", "", "two"]
    end

    test "wraps words before splitting them" do
      assert TextWrap.lines("one two three", 35, 10) == ["one two", " three"]
    end

    test "retains repeated spaces and tabs" do
      text = "one  two\t\tthree"
      assert text |> TextWrap.lines(35, 10) |> Enum.join() == text
    end

    test "accepts zero-size fonts without width wrapping" do
      assert TextWrap.lines("one two\nthree", 0, 0) == ["one two", "three"]
    end
  end

  describe "lines/4" do
    test "measured Helvetica lines fit the available width" do
      text = String.duplicate("A", 29) <> " " <> String.duplicate("A", 24) <> " " <> String.duplicate("A", 45)
      measure = &TextWrap.width("Helvetica", 9, &1)
      lines = TextWrap.lines(text, 360, 9, measure)

      assert length(lines) == 2
      assert Enum.join(lines) == text
      assert Enum.all?(lines, &(measure.(&1) <= 360))
    end
  end
end
