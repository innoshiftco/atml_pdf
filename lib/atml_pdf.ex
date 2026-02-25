defmodule AtmlPdf do
  @moduledoc """
  Public API for rendering ATML templates to PDF.

  ATML (AWB Template Markup Language) is an XML-based format for authoring
  printable Airway Bill label templates.  This module provides two entry
  points:

  - `render/3` — parse, layout, and write a PDF file to disk.
  - `render_binary/2` — parse, layout, and return the PDF as a binary.

  Both functions run the same three-stage pipeline:

      ATML XML string
        → AtmlPdf.Parser    (XML → element structs)
        → AtmlPdf.Layout    (resolve dimensions & font inheritance)
        → AtmlPdf.Renderer  (element tree → PDF via the `pdf` library)

  ## Examples

      iex> xml = ~s|<document width="100pt" height="100pt"></document>|
      iex> {:ok, binary} = AtmlPdf.render_binary(xml)
      iex> is_binary(binary) and byte_size(binary) > 0
      true

  """

  alias AtmlPdf.{Layout, Parser, Renderer}

  @doc """
  Parses `template`, resolves its layout, and writes the resulting PDF to
  `path`.

  Returns `:ok` on success or `{:error, reason}` on failure.

  ## Parameters

  - `template` — ATML XML string.
  - `path` — Destination file path (will be created or overwritten).
  - `opts` — Reserved for future options; currently unused.

  ## Examples

      iex> xml = ~s|<document width="100pt" height="100pt"></document>|
      iex> path = Path.join(System.tmp_dir!(), "atml_test_render.pdf")
      iex> AtmlPdf.render(xml, path)
      :ok
      iex> File.exists?(path)
      true

  """
  @spec render(String.t(), Path.t(), keyword()) :: :ok | {:error, String.t()}
  def render(template, path, opts \\ []) do
    with {:ok, tree} <- Parser.parse(template),
         {:ok, resolved} <- Layout.resolve(tree),
         {:ok, pdf} <- Renderer.render(resolved, opts) do
      Pdf.write_to(pdf, path)
      Pdf.cleanup(pdf)
      :ok
    end
  end

  @doc """
  Parses `template`, resolves its layout, and returns the PDF as a binary.

  Returns `{:ok, binary}` on success or `{:error, reason}` on failure.

  ## Parameters

  - `template` — ATML XML string.
  - `opts` — Reserved for future options; currently unused.

  ## Examples

      iex> xml = ~s|<document width="100pt" height="100pt"></document>|
      iex> {:ok, binary} = AtmlPdf.render_binary(xml)
      iex> is_binary(binary) and byte_size(binary) > 0
      true

  """
  @spec render_binary(String.t(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def render_binary(template, opts \\ []) do
    with {:ok, tree} <- Parser.parse(template),
         {:ok, resolved} <- Layout.resolve(tree),
         {:ok, pdf} <- Renderer.render(resolved, opts) do
      binary = Pdf.export(pdf)
      Pdf.cleanup(pdf)
      {:ok, binary}
    end
  end
end
