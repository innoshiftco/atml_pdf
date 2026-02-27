defmodule AtmlPdf.MixProject do
  use Mix.Project

  def project do
    [
      app: :atml_pdf,
      version: "1.0.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "AtmlPdf",
      source_url: "https://github.com/innoshiftco/atml_pdf"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:pdf, "~> 0.7"},
      {:sweet_xml, "~> 0.7"},
      {:ex_guten, "~> 0.1"},
      {:barlix, "~> 0.6", only: :test},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Parse ATML (XML-based label layout format) and render to PDF with pluggable backends.
    Supports dimensions, fonts, images, borders, and UTF-8 text.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/innoshiftco/atml_pdf",
        "Changelog" => "https://github.com/innoshiftco/atml_pdf/blob/main/CHANGELOG.md"
      },
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
