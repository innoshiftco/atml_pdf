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
      assert TextWrap.lines("one two three", 35, 10) == ["one two", "three"]
    end
  end
end
