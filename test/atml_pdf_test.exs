defmodule AtmlPdfTest do
  @moduledoc false
  use ExUnit.Case
  doctest AtmlPdf
  doctest AtmlPdf.Renderer

  # ---------------------------------------------------------------------------
  # End-to-end: render_binary/2 on the full spec example
  # ---------------------------------------------------------------------------

  @full_example_xml """
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

  describe "render_binary/2" do
    test "returns {:ok, binary} for the full spec example" do
      assert {:ok, binary} = AtmlPdf.render_binary(@full_example_xml)
      assert is_binary(binary)
      assert byte_size(binary) > 0
    end

    test "produced binary starts with PDF header" do
      {:ok, binary} = AtmlPdf.render_binary(@full_example_xml)
      assert binary =~ "%PDF-"
    end

    test "returns {:ok, binary} for a minimal document" do
      xml = ~s|<document width="100pt" height="100pt"></document>|
      assert {:ok, binary} = AtmlPdf.render_binary(xml)
      assert byte_size(binary) > 0
    end

    test "returns {:error, _} for malformed XML" do
      assert {:error, _} = AtmlPdf.render_binary("<not valid xml")
    end
  end

  describe "render/3" do
    test "writes a PDF file to disk for the full spec example" do
      path =
        Path.join(System.tmp_dir!(), "atml_e2e_test_#{:erlang.unique_integer([:positive])}.pdf")

      try do
        assert :ok = AtmlPdf.render(@full_example_xml, path)
        assert File.exists?(path)
        assert File.stat!(path).size > 0
      after
        File.rm(path)
      end
    end
  end
end
