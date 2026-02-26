#!/usr/bin/env elixir
#
# Demo script showing the adapter pattern in action
#

Mix.install([{:atml_pdf, path: "."}])

xml = """
<document width="400pt" height="200pt" font-family="Helvetica" font-size="10pt">
  <row height="60pt" border-bottom="solid 2pt #000000">
    <col width="fill" vertical-align="center" text-align="center"
         font-size="18pt" font-weight="bold">
      ADAPTER PATTERN DEMO
    </col>
  </row>

  <row height="70pt" border-bottom="solid 1pt #cccccc">
    <col width="50%" padding="10pt" border-right="solid 1pt #cccccc">
      <row height="fit">
        <col font-weight="bold" font-size="8pt">BACKEND</col>
      </row>
      <row height="fill">
        <col padding-top="4pt">PdfAdapter (default)</col>
      </row>
    </col>
    <col width="fill" padding="10pt">
      <row height="fit">
        <col font-weight="bold" font-size="8pt">ENCODING</col>
      </row>
      <row height="fill">
        <col padding-top="4pt">WinAnsi (ASCII + Latin-1)</col>
      </row>
    </col>
  </row>

  <row height="fill">
    <col width="fill" padding="10pt" vertical-align="center" text-align="center">
      Backend switching works!
    </col>
  </row>
</document>
"""

IO.puts("Rendering with default backend (PdfAdapter)...")
output_default = "/tmp/adapter_demo_default.pdf"

case AtmlPdf.render(xml, output_default) do
  :ok ->
    IO.puts("✓ Success: #{output_default}")
    IO.puts("  File size: #{File.stat!(output_default).size} bytes")

  {:error, reason} ->
    IO.puts("✗ Error: #{reason}")
end

IO.puts("\nRendering with explicit backend option...")
output_explicit = "/tmp/adapter_demo_explicit.pdf"

case AtmlPdf.render(xml, output_explicit, backend: AtmlPdf.PdfBackend.PdfAdapter) do
  :ok ->
    IO.puts("✓ Success: #{output_explicit}")
    IO.puts("  File size: #{File.stat!(output_explicit).size} bytes")

  {:error, reason} ->
    IO.puts("✗ Error: #{reason}")
end

IO.puts("\nRendering to binary...")

case AtmlPdf.render_binary(xml) do
  {:ok, binary} ->
    IO.puts("✓ Success: generated #{byte_size(binary)} byte PDF")
    IO.puts("  PDF header: #{String.slice(binary, 0, 8)}")

  {:error, reason} ->
    IO.puts("✗ Error: #{reason}")
end

IO.puts("\n✅ Adapter pattern implementation complete!")
IO.puts("\nNext steps:")
IO.puts("  1. Implement ExGutenAdapter for UTF-8 support")
IO.puts("  2. Add TrueType font management")
IO.puts("  3. Create parameterized tests for both backends")
