defmodule AtmlPdf.PdfBackend.ExGutenAdapterTest do
  use ExUnit.Case, async: true

  alias AtmlPdf.PdfBackend.ExGutenAdapter

  @noto_sans_ttf Path.join([:code.priv_dir(:atml_pdf), "fonts", "NotoSans-Regular.ttf"])

  describe "new/3" do
    test "creates a new PDF with specified dimensions" do
      assert {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      assert %ExGuten.PDF{} = pdf
    end

    test "accepts options" do
      assert {:ok, pdf} = ExGutenAdapter.new(400, 600, compress: true)
      assert %ExGuten.PDF{} = pdf
    end

    test "registers NotoSans when priv/fonts/NotoSans-Regular.ttf exists" do
      if File.exists?(@noto_sans_ttf) do
        {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
        assert Map.has_key?(pdf.embedded_fonts, "NotoSans")
      end
    end

    test "registers fonts from application config" do
      original = Application.get_env(:atml_pdf, :fonts, [])

      Application.put_env(:atml_pdf, :fonts, [
        {"NotoSans-Config", @noto_sans_ttf}
      ])

      try do
        {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
        assert Map.has_key?(pdf.embedded_fonts, "NotoSans-Config")
      after
        Application.put_env(:atml_pdf, :fonts, original)
      end
    end

    test "skips config font with missing file" do
      original = Application.get_env(:atml_pdf, :fonts, [])

      Application.put_env(:atml_pdf, :fonts, [
        {"GhostFont", "/tmp/does_not_exist_#{:erlang.unique_integer([:positive])}.ttf"}
      ])

      try do
        assert {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
        refute Map.has_key?(pdf.embedded_fonts, "GhostFont")
      after
        Application.put_env(:atml_pdf, :fonts, original)
      end
    end

    test "skips malformed config font entries" do
      original = Application.get_env(:atml_pdf, :fonts, [])

      Application.put_env(:atml_pdf, :fonts, [:bad_entry, 123, {"OnlyName"}])

      try do
        assert {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
        assert %ExGuten.PDF{} = pdf
      after
        Application.put_env(:atml_pdf, :fonts, original)
      end
    end
  end

  describe "set_font/4" do
    test "sets Helvetica font" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      result = ExGutenAdapter.set_font(pdf, "Helvetica", 12, [])
      assert %ExGuten.PDF{} = result
      assert {"Helvetica", 12} = result.current_font
    end

    test "sets bold Helvetica font" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      result = ExGutenAdapter.set_font(pdf, "Helvetica", 12, bold: true)
      assert %ExGuten.PDF{} = result
      assert {"Helvetica-Bold", 12} = result.current_font
    end

    test "maps Times-Roman font family" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      result = ExGutenAdapter.set_font(pdf, "Times-Roman", 10, [])
      assert %ExGuten.PDF{} = result
      assert {"Times-Roman", 10} = result.current_font
    end

    test "maps NotoSans font family" do
      if File.exists?(@noto_sans_ttf) do
        {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
        result = ExGutenAdapter.set_font(pdf, "NotoSans", 12, [])
        assert %ExGuten.PDF{} = result
        assert {"NotoSans", 12} = result.current_font
      end
    end

    test "unknown font family falls back to NotoSans when registered" do
      if File.exists?(@noto_sans_ttf) do
        {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
        result = ExGutenAdapter.set_font(pdf, "UnknownFont", 12, [])
        assert %ExGuten.PDF{} = result
        assert {"NotoSans", 12} = result.current_font
      end
    end
  end

  describe "text_wrap/5" do
    test "renders ASCII text" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      pdf = ExGutenAdapter.set_font(pdf, "Helvetica", 12, [])
      result = ExGutenAdapter.text_wrap(pdf, {10, 20}, {200, 50}, "Hello World", align: :left)
      assert %ExGuten.PDF{} = result
    end

    test "supports center alignment" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      pdf = ExGutenAdapter.set_font(pdf, "Helvetica", 12, [])
      result = ExGutenAdapter.text_wrap(pdf, {10, 20}, {200, 50}, "Centered", align: :center)
      assert %ExGuten.PDF{} = result
    end

    test "supports right alignment" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      pdf = ExGutenAdapter.set_font(pdf, "Helvetica", 12, [])
      result = ExGutenAdapter.text_wrap(pdf, {10, 20}, {200, 50}, "Right", align: :right)
      assert %ExGuten.PDF{} = result
    end

    test "renders Vietnamese text with NotoSans" do
      if File.exists?(@noto_sans_ttf) do
        {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
        pdf = ExGutenAdapter.set_font(pdf, "NotoSans", 12, [])
        result = ExGutenAdapter.text_wrap(pdf, {10, 20}, {200, 50}, "Nguyễn Văn An", align: :left)
        assert %ExGuten.PDF{} = result
      end
    end

    test "uses all embedded fonts as fallbacks" do
      if File.exists?(@noto_sans_ttf) do
        {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
        pdf = ExGutenAdapter.set_font(pdf, "Helvetica", 12, [])
        # NotoSans is embedded — it should be used as fallback for non-Latin glyphs
        result = ExGutenAdapter.text_wrap(pdf, {10, 20}, {300, 50}, "Hello 科技", align: :left)
        assert %ExGuten.PDF{} = result
      end
    end

    test "renders multiline text" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      pdf = ExGutenAdapter.set_font(pdf, "Helvetica", 12, [])
      long_text = String.duplicate("word ", 30)
      result = ExGutenAdapter.text_wrap(pdf, {10, 300}, {200, 200}, long_text, align: :left)
      assert %ExGuten.PDF{} = result
    end
  end

  describe "set_text_leading/2" do
    test "accepts leading value (no-op in ExGuten)" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      result = ExGutenAdapter.set_text_leading(pdf, 14)
      assert %ExGuten.PDF{} = result
    end
  end

  describe "set_stroke_color/2" do
    test "sets black color" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      result = ExGutenAdapter.set_stroke_color(pdf, :black)
      assert %ExGuten.PDF{} = result
    end

    test "sets RGB color (0-255 range)" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      result = ExGutenAdapter.set_stroke_color(pdf, {255, 0, 0})
      assert %ExGuten.PDF{} = result
    end

    test "sets RGB color (0.0-1.0 range)" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      result = ExGutenAdapter.set_stroke_color(pdf, {1.0, 0.0, 0.0})
      assert %ExGuten.PDF{} = result
    end
  end

  describe "set_line_width/2" do
    test "sets line width" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      result = ExGutenAdapter.set_line_width(pdf, 2.0)
      assert %ExGuten.PDF{} = result
    end
  end

  describe "line/3" do
    test "draws a line" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      result = ExGutenAdapter.line(pdf, {10, 10}, {100, 100})
      assert %ExGuten.PDF{} = result
    end
  end

  describe "stroke/1" do
    test "strokes the current path" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      pdf = ExGutenAdapter.line(pdf, {10, 10}, {100, 100})
      result = ExGutenAdapter.stroke(pdf)
      assert %ExGuten.PDF{} = result
    end
  end

  describe "size/1" do
    test "returns page dimensions" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      assert {400.0, 600.0} = ExGutenAdapter.size(pdf)
    end
  end

  describe "export/1" do
    test "exports PDF as binary" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      binary = ExGutenAdapter.export(pdf)
      assert is_binary(binary)
      assert String.starts_with?(binary, "%PDF-")
    end
  end

  describe "write_to/2" do
    test "writes PDF to file" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])

      path =
        Path.join(System.tmp_dir!(), "ex_guten_test_#{:erlang.unique_integer([:positive])}.pdf")

      assert :ok = ExGutenAdapter.write_to(pdf, path)
      assert File.exists?(path)

      File.rm(path)
    end
  end

  describe "cleanup/1" do
    test "cleanup succeeds (no-op for immutable structs)" do
      {:ok, pdf} = ExGutenAdapter.new(400, 600, [])
      assert :ok = ExGutenAdapter.cleanup(pdf)
    end
  end

  describe "add_image/4" do
    @tag :skip
    test "adds image from file path" do
      # Skip this test - requires actual image file
      {:ok, _pdf} = ExGutenAdapter.new(400, 600, [])
    end

    @tag :skip
    test "adds image from binary data" do
      # Skip this test - requires actual image binary
      {:ok, _pdf} = ExGutenAdapter.new(400, 600, [])
    end
  end
end
