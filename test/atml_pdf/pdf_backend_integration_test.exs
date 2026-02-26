defmodule AtmlPdf.PdfBackendIntegrationTest do
  @moduledoc """
  Integration tests verifying that the adapter pattern works correctly
  with the full ATML pipeline.
  """
  use ExUnit.Case, async: true

  @simple_xml """
  <document width="200pt" height="100pt" font-family="Helvetica" font-size="12pt">
    <row height="fill">
      <col width="fill">Hello, World!</col>
    </row>
  </document>
  """

  describe "PdfAdapter backend (default)" do
    test "renders via application config default" do
      assert {:ok, binary} = AtmlPdf.render_binary(@simple_xml)
      assert is_binary(binary)
      assert binary =~ "%PDF-"
    end

    test "renders via explicit backend option" do
      assert {:ok, binary} =
               AtmlPdf.render_binary(@simple_xml, backend: AtmlPdf.PdfBackend.PdfAdapter)

      assert is_binary(binary)
      assert binary =~ "%PDF-"
    end

    test "writes to file with backend option" do
      path = Path.join(System.tmp_dir!(), "backend_test_#{:erlang.unique_integer()}.pdf")

      assert :ok =
               AtmlPdf.render(@simple_xml, path, backend: AtmlPdf.PdfBackend.PdfAdapter)

      assert File.exists?(path)
      File.rm(path)
    end
  end

  describe "backend configuration" do
    test "uses Application config if set" do
      # Save original config
      original = Application.get_env(:atml_pdf, :pdf_backend)

      try do
        # Set backend via config
        Application.put_env(:atml_pdf, :pdf_backend, AtmlPdf.PdfBackend.PdfAdapter)

        assert {:ok, binary} = AtmlPdf.render_binary(@simple_xml)
        assert is_binary(binary)
      after
        # Restore original config
        if original do
          Application.put_env(:atml_pdf, :pdf_backend, original)
        else
          Application.delete_env(:atml_pdf, :pdf_backend)
        end
      end
    end

    test "option overrides Application config" do
      # Save original config
      original = Application.get_env(:atml_pdf, :pdf_backend)

      try do
        # Set a config (doesn't matter what since we'll override)
        Application.put_env(:atml_pdf, :pdf_backend, AtmlPdf.PdfBackend.PdfAdapter)

        # Override with option - should use PdfAdapter
        assert {:ok, binary} =
                 AtmlPdf.render_binary(@simple_xml, backend: AtmlPdf.PdfBackend.PdfAdapter)

        assert is_binary(binary)
      after
        # Restore original config
        if original do
          Application.put_env(:atml_pdf, :pdf_backend, original)
        else
          Application.delete_env(:atml_pdf, :pdf_backend)
        end
      end
    end
  end

  describe "complex documents with backend" do
    test "renders document with images" do
      # Minimal 1×1 white pixel PNG
      tiny_png =
        <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
          8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 8, 215, 99, 248, 207,
          192, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

      data_uri = "data:image/png;base64,#{Base.encode64(tiny_png)}"

      xml = """
      <document width="200pt" height="150pt">
        <row height="fill">
          <col width="fill">
            <img src="#{data_uri}" width="50pt" height="50pt" />
          </col>
        </row>
      </document>
      """

      assert {:ok, binary} =
               AtmlPdf.render_binary(xml, backend: AtmlPdf.PdfBackend.PdfAdapter)

      assert is_binary(binary)
    end

    test "renders document with borders" do
      xml = """
      <document width="200pt" height="100pt">
        <row height="50pt" border-bottom="solid 2pt #000000">
          <col width="100pt" border-right="solid 1pt #cccccc">Left</col>
          <col width="fill">Right</col>
        </row>
      </document>
      """

      assert {:ok, binary} =
               AtmlPdf.render_binary(xml, backend: AtmlPdf.PdfBackend.PdfAdapter)

      assert is_binary(binary)
    end

    test "renders document with nested rows" do
      xml = """
      <document width="200pt" height="200pt">
        <row height="100pt">
          <col width="fill">
            <row height="50pt">
              <col width="fill">Nested 1</col>
            </row>
            <row height="50pt">
              <col width="fill">Nested 2</col>
            </row>
          </col>
        </row>
      </document>
      """

      assert {:ok, binary} =
               AtmlPdf.render_binary(xml, backend: AtmlPdf.PdfBackend.PdfAdapter)

      assert is_binary(binary)
    end

    test "renders document with font overrides" do
      xml = """
      <document width="200pt" height="100pt" font-family="Helvetica" font-size="10pt">
        <row height="50pt">
          <col width="fill" font-size="14pt" font-weight="bold">Large Bold</col>
        </row>
        <row height="50pt">
          <col width="fill" font-family="Times-Roman" font-size="8pt">Small Times</col>
        </row>
      </document>
      """

      assert {:ok, binary} =
               AtmlPdf.render_binary(xml, backend: AtmlPdf.PdfBackend.PdfAdapter)

      assert is_binary(binary)
    end

    test "renders document with various alignments" do
      xml = """
      <document width="200pt" height="150pt">
        <row height="50pt">
          <col width="fill" text-align="left" vertical-align="top">Top Left</col>
        </row>
        <row height="50pt">
          <col width="fill" text-align="center" vertical-align="center">Center Center</col>
        </row>
        <row height="50pt">
          <col width="fill" text-align="right" vertical-align="bottom">Bottom Right</col>
        </row>
      </document>
      """

      assert {:ok, binary} =
               AtmlPdf.render_binary(xml, backend: AtmlPdf.PdfBackend.PdfAdapter)

      assert is_binary(binary)
    end
  end
end
