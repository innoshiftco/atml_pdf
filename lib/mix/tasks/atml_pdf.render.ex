defmodule Mix.Tasks.AtmlPdf.Render do
  @shortdoc "Render an ATML template file to PDF"

  @moduledoc """
  Renders an ATML XML template file to a PDF file.

  ## Usage

      mix atml_pdf.render TEMPLATE [OUTPUT] [OPTIONS]

  ## Arguments

  * `TEMPLATE` — path to the ATML XML template file (required)
  * `OUTPUT`   — path for the output PDF file (optional).
                 Defaults to the template path with the extension replaced by `.pdf`.

  ## Options

  * `--backend BACKEND` — PDF backend to use (PdfAdapter or ExGutenAdapter).
                          Defaults to application config or PdfAdapter.
  * `--single-page`     — Trim output to a single page; overflow rows are clipped.
                          By default, content automatically expands across multiple pages.

  ## Examples

      # Write output next to the template
      mix atml_pdf.render label.xml

      # Explicit output path
      mix atml_pdf.render label.xml /tmp/label.pdf

      # Use ExGuten backend for UTF-8 support
      mix atml_pdf.render label.xml /tmp/label.pdf --backend ExGutenAdapter

      # Multi-page order example (auto page split, default)
      mix atml_pdf.render examples/multi_page_order.xml --backend ExGutenAdapter

      # Trim to single page — overflow rows are clipped
      mix atml_pdf.render label.xml /tmp/label.pdf --single-page

      # Absolute paths
      mix atml_pdf.render /path/to/template.xml /path/to/output.pdf

  ## Exit codes

  * `0` — success
  * `1` — missing argument, file not found, parse error, or render error

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Ensure the application and its deps are started so Pdf.* calls work.
    Mix.Task.run("app.start")

    case parse_args(args) do
      {:ok, template_path, output_path, opts} ->
        render(template_path, output_path, opts)

      {:error, message} ->
        Mix.shell().error(message)
        Mix.shell().error("Usage: mix atml_pdf.render TEMPLATE [OUTPUT] [--backend BACKEND] [--single-page]")
        exit({:shutdown, 1})
    end
  end

  # ---------------------------------------------------------------------------
  # Argument parsing
  # ---------------------------------------------------------------------------

  defp parse_args([]), do: {:error, "Error: TEMPLATE argument is required."}

  defp parse_args(args) do
    {opts, positional, _invalid} =
      OptionParser.parse(args,
        strict: [backend: :string, single_page: :boolean],
        aliases: [b: :backend]
      )

    render_opts =
      parse_backend_opt(opts) ++
        parse_single_page_opt(opts)

    case positional do
      [template] ->
        output = Path.rootname(template) <> ".pdf"
        {:ok, template, output, render_opts}

      [template, output | _extra] ->
        {:ok, template, output, render_opts}

      _ ->
        {:error, "Error: Invalid arguments."}
    end
  end

  defp parse_backend_opt(opts) do
    case Keyword.get(opts, :backend) do
      nil ->
        []

      "PdfAdapter" ->
        [backend: AtmlPdf.PdfBackend.PdfAdapter]

      "ExGutenAdapter" ->
        [backend: AtmlPdf.PdfBackend.ExGutenAdapter]

      backend ->
        Mix.shell().info("Unknown backend: #{backend}, using default")
        []
    end
  end

  defp parse_single_page_opt(opts) do
    if Keyword.get(opts, :single_page, false), do: [multiple_page: false], else: []
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  defp render(template_path, output_path, opts) do
    backend_name =
      case Keyword.get(opts, :backend) do
        AtmlPdf.PdfBackend.PdfAdapter -> "PdfAdapter"
        AtmlPdf.PdfBackend.ExGutenAdapter -> "ExGutenAdapter"
        nil -> "default"
        other -> inspect(other)
      end

    with {:read, {:ok, xml}} <- {:read, File.read(template_path)},
         {:render, :ok} <- {:render, AtmlPdf.render(xml, output_path, opts)} do
      Mix.shell().info("Backend: #{backend_name}")
      Mix.shell().info("Written: #{output_path}")
    else
      {:read, {:error, reason}} ->
        Mix.shell().error(
          "Error: cannot read \"#{template_path}\": #{:file.format_error(reason)}"
        )

        exit({:shutdown, 1})

      {:render, {:error, reason}} ->
        Mix.shell().error("Error: render failed: #{reason}")
        exit({:shutdown, 1})
    end
  end
end
