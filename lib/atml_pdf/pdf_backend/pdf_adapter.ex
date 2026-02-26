defmodule AtmlPdf.PdfBackend.PdfAdapter do
  @moduledoc """
  Adapter for the `pdf` hex package (v0.7).

  This adapter wraps the existing `pdf` library to conform to the
  `AtmlPdf.PdfBackend` behaviour. The `pdf` library uses a process-based
  API where the PDF state is held in a GenServer process.

  ## Features

  - WinAnsi encoding (ASCII + 128 Latin-1 characters)
  - Type 1 PostScript fonts (Helvetica, Times-Roman, Courier)
  - PNG and JPEG image embedding
  - Compression support

  ## Limitations

  - No UTF-8 support (only WinAnsi encoding)
  - No TrueType/OpenType font embedding
  - Limited to built-in fonts
  """

  @behaviour AtmlPdf.PdfBackend

  @impl true
  def new(width, height, opts) do
    compress = Keyword.get(opts, :compress, false)
    {:ok, pid} = Pdf.new(size: [width, height], compress: compress)
    {:ok, pid}
  end

  @impl true
  def set_font(pid, family, size, opts) do
    bold = Keyword.get(opts, :bold, false)
    Pdf.set_font(pid, family, round(size), bold: bold)
    pid
  end

  @impl true
  def text_wrap(pid, {x, y}, {width, height}, text, opts) do
    align = Keyword.get(opts, :align, :left)
    Pdf.text_wrap(pid, {x, y}, {width, height}, text, align: align)
    pid
  end

  @impl true
  def set_text_leading(pid, leading) do
    Pdf.set_text_leading(pid, round(leading))
    pid
  end

  @impl true
  def add_image(pid, image_data, {x, y}, {width, height}) do
    Pdf.add_image(pid, {x, y}, image_data, width: width, height: height)
    pid
  end

  @impl true
  def set_stroke_color(pid, color) do
    Pdf.set_stroke_color(pid, color)
    pid
  end

  @impl true
  def set_line_width(pid, width) do
    Pdf.set_line_width(pid, width)
    pid
  end

  @impl true
  def line(pid, from, to) do
    Pdf.line(pid, from, to)
    pid
  end

  @impl true
  def stroke(pid) do
    Pdf.stroke(pid)
    pid
  end

  @impl true
  def size(pid) do
    %{width: w, height: h} = Pdf.size(pid)
    {w, h}
  end

  @impl true
  def export(pid) do
    Pdf.export(pid)
  end

  @impl true
  def write_to(pid, path) do
    Pdf.write_to(pid, path)
    :ok
  end

  @impl true
  def cleanup(pid) do
    Pdf.cleanup(pid)
  end
end
