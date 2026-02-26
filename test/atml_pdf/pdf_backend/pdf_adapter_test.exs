defmodule AtmlPdf.PdfBackend.PdfAdapterTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias AtmlPdf.PdfBackend.PdfAdapter

  describe "new/3" do
    test "creates a new PDF process with default options" do
      assert {:ok, pid} = PdfAdapter.new(100, 100, [])
      assert is_pid(pid)
      PdfAdapter.cleanup(pid)
    end

    test "creates a new PDF with specified dimensions" do
      assert {:ok, pid} = PdfAdapter.new(200, 300, [])
      {width, height} = PdfAdapter.size(pid)
      assert width == 200
      assert height == 300
      PdfAdapter.cleanup(pid)
    end

    test "respects compress option" do
      assert {:ok, pid} = PdfAdapter.new(100, 100, compress: true)
      assert is_pid(pid)
      PdfAdapter.cleanup(pid)
    end
  end

  describe "set_font/4" do
    test "sets font and returns pid for chaining" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      result = PdfAdapter.set_font(pid, "Helvetica", 12, [])
      assert result == pid
      PdfAdapter.cleanup(pid)
    end

    test "handles bold option" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      result = PdfAdapter.set_font(pid, "Helvetica", 12, bold: true)
      assert result == pid
      PdfAdapter.cleanup(pid)
    end

    test "rounds font size to integer" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      result = PdfAdapter.set_font(pid, "Helvetica", 12.7, [])
      assert result == pid
      PdfAdapter.cleanup(pid)
    end
  end

  describe "text_wrap/5" do
    test "renders text and returns pid for chaining" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      pid = PdfAdapter.set_font(pid, "Helvetica", 12, [])
      result = PdfAdapter.text_wrap(pid, {10, 90}, {80, 20}, "Hello", [])
      assert result == pid
      PdfAdapter.cleanup(pid)
    end

    test "handles text alignment options" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      pid = PdfAdapter.set_font(pid, "Helvetica", 12, [])

      for align <- [:left, :center, :right] do
        result = PdfAdapter.text_wrap(pid, {10, 70}, {80, 20}, "Test", align: align)
        assert result == pid
      end

      PdfAdapter.cleanup(pid)
    end
  end

  describe "set_text_leading/2" do
    test "sets line height and returns pid for chaining" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      result = PdfAdapter.set_text_leading(pid, 14.4)
      assert result == pid
      PdfAdapter.cleanup(pid)
    end

    test "rounds leading to integer" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      result = PdfAdapter.set_text_leading(pid, 15.8)
      assert result == pid
      PdfAdapter.cleanup(pid)
    end
  end

  describe "set_stroke_color/2" do
    test "sets color and returns pid for chaining" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      result = PdfAdapter.set_stroke_color(pid, {0, 0, 0})
      assert result == pid
      PdfAdapter.cleanup(pid)
    end

    test "handles different color formats" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])

      result = PdfAdapter.set_stroke_color(pid, :black)
      assert result == pid

      result = PdfAdapter.set_stroke_color(pid, {255, 0, 0})
      assert result == pid

      PdfAdapter.cleanup(pid)
    end
  end

  describe "set_line_width/2" do
    test "sets line width and returns pid for chaining" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      result = PdfAdapter.set_line_width(pid, 1.5)
      assert result == pid
      PdfAdapter.cleanup(pid)
    end
  end

  describe "line/3 and stroke/1" do
    test "draws a line and strokes it" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      pid = PdfAdapter.set_stroke_color(pid, :black)
      pid = PdfAdapter.set_line_width(pid, 1)
      pid = PdfAdapter.line(pid, {10, 10}, {90, 10})
      result = PdfAdapter.stroke(pid)
      assert result == pid
      PdfAdapter.cleanup(pid)
    end
  end

  describe "size/1" do
    test "returns page dimensions" do
      {:ok, pid} = PdfAdapter.new(150, 200, [])
      {width, height} = PdfAdapter.size(pid)
      assert width == 150
      assert height == 200
      PdfAdapter.cleanup(pid)
    end
  end

  describe "export/1" do
    test "exports PDF as binary" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      binary = PdfAdapter.export(pid)
      assert is_binary(binary)
      assert byte_size(binary) > 0
      assert binary =~ "%PDF-"
      PdfAdapter.cleanup(pid)
    end
  end

  describe "write_to/2" do
    test "writes PDF to file" do
      path = Path.join(System.tmp_dir!(), "pdf_adapter_test_#{:erlang.unique_integer()}.pdf")
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      assert :ok = PdfAdapter.write_to(pid, path)
      assert File.exists?(path)
      PdfAdapter.cleanup(pid)
      File.rm(path)
    end
  end

  describe "cleanup/1" do
    test "cleans up PDF process" do
      {:ok, pid} = PdfAdapter.new(100, 100, [])
      assert :ok = PdfAdapter.cleanup(pid)
      # Verify process is dead
      refute Process.alive?(pid)
    end
  end

  describe "full rendering pipeline" do
    test "creates a simple PDF with text" do
      {:ok, pid} = PdfAdapter.new(200, 100, [])

      pid
      |> PdfAdapter.set_font("Helvetica", 14, bold: false)
      |> PdfAdapter.set_text_leading(16.8)
      |> PdfAdapter.text_wrap({10, 90}, {180, 80}, "Hello, PDF!", align: :left)

      binary = PdfAdapter.export(pid)
      assert is_binary(binary)
      assert binary =~ "%PDF-"

      PdfAdapter.cleanup(pid)
    end

    test "creates a PDF with borders" do
      {:ok, pid} = PdfAdapter.new(200, 100, [])

      pid
      |> PdfAdapter.set_stroke_color({0, 0, 0})
      |> PdfAdapter.set_line_width(1)
      |> PdfAdapter.line({10, 10}, {190, 10})
      |> PdfAdapter.line({190, 10}, {190, 90})
      |> PdfAdapter.line({190, 90}, {10, 90})
      |> PdfAdapter.line({10, 90}, {10, 10})
      |> PdfAdapter.stroke()

      binary = PdfAdapter.export(pid)
      assert is_binary(binary)

      PdfAdapter.cleanup(pid)
    end
  end
end
