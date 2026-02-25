defmodule Mix.Tasks.AtmlPdf.Render do
  @shortdoc "Render an ATML template file to PDF"

  @moduledoc """
  Renders an ATML XML template file to a PDF file.

  ## Usage

      mix atml_pdf.render TEMPLATE [OUTPUT]

  ## Arguments

  * `TEMPLATE` — path to the ATML XML template file (required)
  * `OUTPUT`   — path for the output PDF file (optional).
                 Defaults to the template path with the extension replaced by `.pdf`.

  ## Examples

      # Write output next to the template
      mix atml_pdf.render label.xml

      # Explicit output path
      mix atml_pdf.render label.xml /tmp/label.pdf

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
      {:ok, template_path, output_path} ->
        render(template_path, output_path)

      {:error, message} ->
        Mix.shell().error(message)
        Mix.shell().error("Usage: mix atml_pdf.render TEMPLATE [OUTPUT]")
        exit({:shutdown, 1})
    end
  end

  # ---------------------------------------------------------------------------
  # Argument parsing
  # ---------------------------------------------------------------------------

  defp parse_args([]), do: {:error, "Error: TEMPLATE argument is required."}

  defp parse_args([template]) do
    output = Path.rootname(template) <> ".pdf"
    {:ok, template, output}
  end

  defp parse_args([template, output | _]), do: {:ok, template, output}

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  defp render(template_path, output_path) do
    with {:read, {:ok, xml}} <- {:read, File.read(template_path)},
         {:render, :ok} <- {:render, AtmlPdf.render(xml, output_path)} do
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
