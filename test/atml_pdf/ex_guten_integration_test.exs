defmodule AtmlPdf.ExGutenIntegrationTest do
  use ExUnit.Case, async: false

  alias AtmlPdf.PdfBackend.ExGutenAdapter

  @simple_xml """
  <document width="400pt" height="200pt" font-family="Helvetica" font-size="10pt">
    <row height="60pt" border-bottom="solid 2pt #000000">
      <col width="fill" vertical-align="center" text-align="center"
           font-size="18pt" font-weight="bold">
        ExGuten Backend Test
      </col>
    </row>
    <row height="fill">
      <col width="fill" padding="10pt" vertical-align="center">
        This PDF was rendered using the ExGuten backend adapter.
      </col>
    </row>
  </document>
  """

  @utf8_xml """
  <document width="400pt" height="300pt" font-family="Helvetica" font-size="10pt">
    <row height="50pt" border-bottom="solid 1pt #000000">
      <col width="fill" vertical-align="center" text-align="center" font-weight="bold">
        UTF-8 Test
      </col>
    </row>
    <row height="fill">
      <col width="fill" padding="10pt">
        <row height="30pt"><col>English: Hello World</col></row>
        <row height="30pt"><col>French: Bonjour café</col></row>
        <row height="30pt"><col>German: Guten Tag</col></row>
        <row height="30pt"><col>Spanish: Hola señor</col></row>
      </col>
    </row>
  </document>
  """

  describe "render/3 with ExGuten backend" do
    test "renders simple document to file" do
      output =
        Path.join(System.tmp_dir!(), "ex_guten_simple_#{:erlang.unique_integer([:positive])}.pdf")

      assert :ok = AtmlPdf.render(@simple_xml, output, backend: ExGutenAdapter)
      assert File.exists?(output)

      # Verify it's a valid PDF
      {:ok, content} = File.read(output)
      assert String.starts_with?(content, "%PDF-")
      assert byte_size(content) > 100

      File.rm(output)
    end

    test "renders document with special characters" do
      output =
        Path.join(System.tmp_dir!(), "ex_guten_utf8_#{:erlang.unique_integer([:positive])}.pdf")

      assert :ok = AtmlPdf.render(@utf8_xml, output, backend: ExGutenAdapter)
      assert File.exists?(output)

      {:ok, content} = File.read(output)
      assert String.starts_with?(content, "%PDF-")

      File.rm(output)
    end

    test "renders document with borders and styling" do
      xml = """
      <document width="300pt" height="200pt" font-family="Helvetica" font-size="10pt">
        <row height="50pt" border-bottom="solid 2pt #000000">
          <col width="50%" border-right="solid 1pt #cccccc" padding="5pt">
            Left Column
          </col>
          <col width="fill" padding="5pt">
            Right Column
          </col>
        </row>
        <row height="fill">
          <col width="fill" padding="10pt" text-align="center" vertical-align="center">
            Borders and Layout
          </col>
        </row>
      </document>
      """

      output =
        Path.join(
          System.tmp_dir!(),
          "ex_guten_borders_#{:erlang.unique_integer([:positive])}.pdf"
        )

      assert :ok = AtmlPdf.render(xml, output, backend: ExGutenAdapter)
      assert File.exists?(output)

      File.rm(output)
    end
  end

  describe "render_binary/2 with ExGuten backend" do
    test "renders to binary" do
      assert {:ok, binary} = AtmlPdf.render_binary(@simple_xml, backend: ExGutenAdapter)
      assert is_binary(binary)
      assert String.starts_with?(binary, "%PDF-")
      assert byte_size(binary) > 100
    end

    test "binary output is valid PDF" do
      {:ok, binary} = AtmlPdf.render_binary(@simple_xml, backend: ExGutenAdapter)

      # Write to temp file to verify
      output =
        Path.join(System.tmp_dir!(), "ex_guten_binary_#{:erlang.unique_integer([:positive])}.pdf")

      File.write!(output, binary)

      assert File.exists?(output)
      {:ok, content} = File.read(output)
      assert content == binary

      File.rm(output)
    end
  end

  describe "backend comparison" do
    test "ExGuten produces different output than PdfAdapter" do
      {:ok, pdf_binary} =
        AtmlPdf.render_binary(@simple_xml, backend: AtmlPdf.PdfBackend.PdfAdapter)

      {:ok, ex_guten_binary} = AtmlPdf.render_binary(@simple_xml, backend: ExGutenAdapter)

      # Both should be valid PDFs
      assert String.starts_with?(pdf_binary, "%PDF-")
      assert String.starts_with?(ex_guten_binary, "%PDF-")

      # But they will have different internal structures
      # (different libraries generate different PDF structures)
      # We just verify both are non-empty and valid
      assert byte_size(pdf_binary) > 0
      assert byte_size(ex_guten_binary) > 0
    end
  end

  describe "font handling" do
    test "renders with different font families" do
      xml = """
      <document width="300pt" height="150pt" font-family="Times-Roman" font-size="10pt">
        <row height="50pt">
          <col width="fill" padding="5pt" font-family="Helvetica">
            Helvetica Font
          </col>
        </row>
        <row height="50pt">
          <col width="fill" padding="5pt" font-family="Times-Roman">
            Times-Roman Font
          </col>
        </row>
        <row height="fill">
          <col width="fill" padding="5pt" font-family="Courier">
            Courier Font
          </col>
        </row>
      </document>
      """

      output =
        Path.join(System.tmp_dir!(), "ex_guten_fonts_#{:erlang.unique_integer([:positive])}.pdf")

      assert :ok = AtmlPdf.render(xml, output, backend: ExGutenAdapter)
      assert File.exists?(output)

      File.rm(output)
    end

    test "renders with bold text" do
      xml = """
      <document width="300pt" height="100pt" font-family="Helvetica" font-size="10pt">
        <row height="50pt">
          <col width="fill" padding="5pt">
            Normal weight text
          </col>
        </row>
        <row height="fill">
          <col width="fill" padding="5pt" font-weight="bold">
            Bold text
          </col>
        </row>
      </document>
      """

      output =
        Path.join(System.tmp_dir!(), "ex_guten_bold_#{:erlang.unique_integer([:positive])}.pdf")

      assert :ok = AtmlPdf.render(xml, output, backend: ExGutenAdapter)
      assert File.exists?(output)

      File.rm(output)
    end
  end
end
