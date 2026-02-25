defmodule AtmlPdf.RendererTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias AtmlPdf.{Layout, Parser, Renderer}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp resolve!(xml) do
    {:ok, parsed} = Parser.parse(xml)
    {:ok, resolved} = Layout.resolve(parsed)
    resolved
  end

  # ---------------------------------------------------------------------------
  # render/2 — smoke tests
  # ---------------------------------------------------------------------------

  describe "render/2" do
    test "returns {:ok, pid} for a minimal document" do
      doc = resolve!(~s|<document width="100pt" height="100pt"></document>|)
      assert {:ok, pid} = Renderer.render(doc)
      assert is_pid(pid)
      Pdf.cleanup(pid)
    end

    test "pdf export produces a non-empty binary" do
      doc = resolve!(~s|<document width="100pt" height="100pt"></document>|)
      {:ok, pid} = Renderer.render(doc)
      binary = Pdf.export(pid)
      Pdf.cleanup(pid)
      assert is_binary(binary)
      assert byte_size(binary) > 0
    end

    test "pdf binary starts with PDF header" do
      doc = resolve!(~s|<document width="100pt" height="100pt"></document>|)
      {:ok, pid} = Renderer.render(doc)
      binary = Pdf.export(pid)
      Pdf.cleanup(pid)
      assert binary =~ "%PDF-"
    end

    test "renders document with a single row and col containing text" do
      xml = """
      <document width="200pt" height="100pt">
        <row height="50pt">
          <col width="fill">Hello</col>
        </row>
      </document>
      """

      doc = resolve!(xml)
      assert {:ok, pid} = Renderer.render(doc)
      binary = Pdf.export(pid)
      Pdf.cleanup(pid)
      assert byte_size(binary) > 0
    end

    test "renders document with borders" do
      xml = """
      <document width="200pt" height="100pt">
        <row height="50pt" border-bottom="solid 1pt #000000">
          <col width="fill" border-right="solid 1pt #cccccc">text</col>
        </row>
      </document>
      """

      doc = resolve!(xml)
      assert {:ok, pid} = Renderer.render(doc)
      binary = Pdf.export(pid)
      Pdf.cleanup(pid)
      assert byte_size(binary) > 0
    end

    test "renders document with padding on document and elements" do
      xml = """
      <document width="200pt" height="200pt" padding="8pt">
        <row height="50pt" padding="4pt">
          <col width="fill" padding="2pt">padded text</col>
        </row>
      </document>
      """

      doc = resolve!(xml)
      assert {:ok, pid} = Renderer.render(doc)
      binary = Pdf.export(pid)
      Pdf.cleanup(pid)
      assert byte_size(binary) > 0
    end

    test "renders multiple rows" do
      xml = """
      <document width="200pt" height="200pt">
        <row height="50pt">
          <col width="fill">row one</col>
        </row>
        <row height="50pt">
          <col width="fill">row two</col>
        </row>
      </document>
      """

      doc = resolve!(xml)
      assert {:ok, pid} = Renderer.render(doc)
      Pdf.cleanup(pid)
    end

    test "renders multiple cols in a row" do
      xml = """
      <document width="200pt" height="100pt">
        <row height="50pt">
          <col width="100pt">left</col>
          <col width="fill">right</col>
        </row>
      </document>
      """

      doc = resolve!(xml)
      assert {:ok, pid} = Renderer.render(doc)
      Pdf.cleanup(pid)
    end

    test "renders nested rows inside a col" do
      xml = """
      <document width="200pt" height="200pt">
        <row height="100pt">
          <col width="fill">
            <row height="50pt">
              <col width="fill">nested text</col>
            </row>
          </col>
        </row>
      </document>
      """

      doc = resolve!(xml)
      assert {:ok, pid} = Renderer.render(doc)
      Pdf.cleanup(pid)
    end

    test "renders font overrides on cols" do
      xml = """
      <document width="200pt" height="100pt" font-family="Helvetica" font-size="8pt">
        <row height="50pt">
          <col width="fill" font-size="14pt" font-weight="bold">big bold text</col>
        </row>
      </document>
      """

      doc = resolve!(xml)
      assert {:ok, pid} = Renderer.render(doc)
      Pdf.cleanup(pid)
    end

    test "renders full spec example template" do
      xml = """
      <document width="400pt" height="600pt" font-family="Helvetica" font-size="8pt">
        <row height="60pt" border-bottom="solid 1pt #000000">
          <col width="80pt" vertical-align="center" text-align="center" padding="4pt">
          </col>
          <col width="fill" vertical-align="center" padding="4pt 8pt"
               font-size="14pt" font-weight="bold" text-align="center">
            AIR WAYBILL
          </col>
        </row>
        <row height="fill" border-bottom="solid 1pt #000000">
          <col width="50%" padding="6pt" border-right="solid 1pt #000000">
            <row height="fit">
              <col font-weight="bold" font-size="7pt">SENDER</col>
            </row>
            <row height="fill">
              <col padding-top="4pt">John Doe, 123 Street, Ho Chi Minh City</col>
            </row>
          </col>
          <col width="fill" padding="6pt">
            <row height="fit">
              <col font-weight="bold" font-size="7pt">RECIPIENT</col>
            </row>
            <row height="fill">
              <col padding-top="4pt">Jane Smith, 456 Avenue, Hanoi</col>
            </row>
          </col>
        </row>
        <row height="40pt" border-bottom="solid 1pt #000000">
          <col width="33%" padding="4pt 6pt" border-right="solid 1pt #000000">
            <row height="fit">
              <col font-weight="bold" font-size="7pt">WEIGHT</col>
            </row>
            <row height="fill">
              <col vertical-align="center">2.5 kg</col>
            </row>
          </col>
          <col width="33%" padding="4pt 6pt" border-right="solid 1pt #000000">
            <row height="fit">
              <col font-weight="bold" font-size="7pt">DIMENSIONS</col>
            </row>
            <row height="fill">
              <col vertical-align="center">30 x 20 x 15 cm</col>
            </row>
          </col>
          <col width="fill" padding="4pt 6pt">
            <row height="fit">
              <col font-weight="bold" font-size="7pt">SERVICE</col>
            </row>
            <row height="fill">
              <col vertical-align="center">Express</col>
            </row>
          </col>
        </row>
        <row height="28pt">
          <col text-align="center" vertical-align="center"
               font-size="11pt" font-weight="bold">
            VN-123456789-SG
          </col>
        </row>
      </document>
      """

      doc = resolve!(xml)
      assert {:ok, pid} = Renderer.render(doc)
      binary = Pdf.export(pid)
      Pdf.cleanup(pid)
      assert is_binary(binary)
      assert byte_size(binary) > 0
    end
  end
end
