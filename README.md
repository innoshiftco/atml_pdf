# atml_pdf

An Elixir library that parses **ATML (AWB Template Markup Language)** — an XML-based format for defining Airway Bill shipping label layouts — and renders the result to PDF.

## Overview

ATML describes a single label as a tree of rows and columns. The library runs a three-stage pipeline:

```
ATML XML string
  → AtmlPdf.Parser    (XML → element structs)
  → AtmlPdf.Layout    (resolve dimensions, font inheritance)
  → AtmlPdf.Renderer  (element tree → PDF via the pdf library)
```

## Demo

![Shipping label rendered by atml_pdf](docs/img/demo.jpg)

## Installation

Add `atml_pdf` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:atml_pdf, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Command line

Render a template file to PDF directly from the shell:

```bash
# Output written next to the template (label.pdf)
mix atml_pdf.render label.xml

# Explicit output path
mix atml_pdf.render label.xml /tmp/label.pdf
```

### Render to a file

```elixir
xml = """
<document width="400pt" height="200pt" font-family="Helvetica" font-size="8pt">
  <row height="fill">
    <col width="fill" vertical-align="center" text-align="center"
         font-size="14pt" font-weight="bold">
      AIR WAYBILL
    </col>
  </row>
</document>
"""

:ok = AtmlPdf.render(xml, "/tmp/label.pdf")
```

### Render to binary

```elixir
{:ok, binary} = AtmlPdf.render_binary(xml)
# binary is a valid PDF you can send over HTTP, write to S3, etc.
```

## ATML Language

### Document structure

Every ATML template has a single `<document>` root. Layout is expressed as alternating rows and columns:

```xml
<document width="400pt" height="600pt" font-family="Helvetica" font-size="8pt">

  <row height="60pt" border-bottom="solid 1pt #000000">
    <col width="80pt" vertical-align="center" padding="4pt">
      <img src="/assets/logo.png" width="60pt" height="40pt" />
    </col>
    <col width="fill" vertical-align="center" font-size="14pt" font-weight="bold"
         text-align="center">
      AIR WAYBILL
    </col>
  </row>

  <row height="fill" border-bottom="solid 1pt #000000">
    <col width="50%" padding="6pt" border-right="solid 1pt #000000">
      <row height="fit"><col font-weight="bold" font-size="7pt">SENDER</col></row>
      <row height="fill"><col padding-top="4pt">John Doe, 123 Street</col></row>
    </col>
    <col width="fill" padding="6pt">
      <row height="fit"><col font-weight="bold" font-size="7pt">RECIPIENT</col></row>
      <row height="fill"><col padding-top="4pt">Jane Smith, 456 Avenue</col></row>
    </col>
  </row>

  <row height="28pt">
    <col text-align="center" vertical-align="center"
         font-size="11pt" font-weight="bold">
      VN-123456789-SG
    </col>
  </row>

</document>
```

### Nesting rules

```
<document>
  └── <row>
        └── <col>
              ├── text
              ├── <img>
              └── <row>        ← nest rows inside cols to subdivide further
                    └── <col>
```

- `<document>` → `<row>` children only
- `<row>` → `<col>` children only
- `<col>` → text, `<img>`, or `<row>` (mixed content allowed)
- A `<col>` cannot be a direct child of another `<col>`

### Dimensions

| Value | Example | Meaning |
|---|---|---|
| Points | `100pt` | Fixed size (1 pt = 1/72 inch) |
| Pixels | `120px` | Fixed size (1 px = 0.75 pt) |
| Percentage | `50%` | Relative to parent container |
| `fill` | `fill` | Consume all remaining space; split equally among `fill` siblings |
| `fit` | `fit` | Shrink-wrap to content size |

### Spacing (padding)

```xml
padding="4pt"              <!-- all sides -->
padding="4pt 8pt"          <!-- top+bottom | left+right -->
padding="2pt 4pt 2pt 4pt"  <!-- top | right | bottom | left -->
padding-top="4pt"          <!-- per-side override -->
```

### Borders

```xml
border="solid 1pt #000000"
border-bottom="dashed 1pt #cccccc"
border-right="dotted 2px #aaaaaa"
border-top="none"
```

Format: `<style> <width> <color>` where style is `solid`, `dashed`, or `dotted`,
width is `<n>pt` or `<n>px`, and color is `#rrggbb` or `#rgb`.

### Fonts

Font attributes cascade from `<document>` down through all descendants. A child
overrides only the attribute it declares; the rest continue to inherit.

```xml
<document font-family="Helvetica" font-size="8pt" font-weight="normal">
  <row>
    <col font-size="12pt">          <!-- inherits family and weight -->
      <row>
        <col font-weight="bold">    <!-- inherits family and 12pt size -->
        </col>
      </row>
    </col>
  </row>
</document>
```

| Attribute | Values | Default |
|---|---|---|
| `font-family` | any font name | `"Helvetica"` |
| `font-size` | `<n>pt` | `8pt` |
| `font-weight` | `normal` \| `bold` | `normal` |

### Alignment

| Attribute | Values | Default |
|---|---|---|
| `text-align` | `left` \| `center` \| `right` | `left` |
| `vertical-align` | `top` \| `center` \| `bottom` | `top` |

### Images (`<img>`)

`<img>` must be a direct child of `<col>`. Three `src` formats are supported:

```xml
<!-- Local file path -->
<img src="/path/to/logo.png" width="60pt" height="40pt" />

<!-- Standard data URI (browser / tool default) -->
<img src="data:image/png;base64,iVBORw0KGgo..." width="60pt" height="40pt" />

<!-- Legacy base64 prefix -->
<img src="base64:iVBORw0KGgo..." width="60pt" height="40pt" />
```

Supported MIME types in data URIs: `image/png`, `image/jpeg`, `image/gif`,
`image/webp`.

**Scaling behaviour:**

- One axis fixed, other `fit` → proportional scaling
- Both fixed → stretch to fill (no aspect ratio preservation)
- Both `fit` → intrinsic size

### Barcodes

Generate a barcode PNG with [Barlix](https://hex.pm/packages/barlix), encode it
as a data URI, and pass it as an `<img src>`:

```elixir
barcode_src =
  "VN-123456789-SG"
  |> Barlix.Code128.encode!()
  |> Barlix.PNG.print(xdim: 2, height: 40, margin: 4)
  |> then(fn {:ok, iodata} ->
    "data:image/png;base64," <> Base.encode64(IO.iodata_to_binary(iodata))
  end)
```

```xml
<img src="data:image/png;base64,..." width="300pt" height="40pt" />
```

Barlix supports Code39, Code93, Code128, ITF, EAN13, and UPC-E. Add it to your
deps:

```elixir
{:barlix, "~> 0.6"}
```

## Mix Task

`mix atml_pdf.render` renders an ATML template file to a PDF file without
writing any Elixir code.

```
mix atml_pdf.render TEMPLATE [OUTPUT]
```

| Argument | Required | Description |
|---|---|---|
| `TEMPLATE` | yes | Path to the ATML XML template file |
| `OUTPUT` | no | Destination PDF path. Defaults to the template path with `.pdf` extension |

```bash
# Minimal — output written as label.pdf in the same directory
mix atml_pdf.render label.xml

# Explicit output path
mix atml_pdf.render templates/waybill.xml /tmp/output.pdf

# Absolute paths work too
mix atml_pdf.render /data/templates/label.xml /data/output/label.pdf
```

Exit codes: `0` on success, `1` on any error (missing file, parse failure,
render failure).

## Backend Configuration

atml_pdf uses a pluggable backend system for PDF generation. This allows you to switch between different PDF libraries based on your needs.

### Available Backends

| Backend | Description | UTF-8 Support | Status |
|---|---|---|---|
| `AtmlPdf.PdfBackend.PdfAdapter` | Default backend using the `pdf` hex package. Supports WinAnsi encoding only. | ❌ ASCII + Latin-1 | ✅ Stable |
| `AtmlPdf.PdfBackend.ExGutenAdapter` | ExGuten backend with full UTF-8 support and immutable API. | ✅ Full Unicode | ✅ Available |

### Configuration

**Application-level configuration** (affects all render calls):

```elixir
# config/config.exs
config :atml_pdf,
  pdf_backend: AtmlPdf.PdfBackend.PdfAdapter  # Default (WinAnsi only)

# Or use ExGuten for UTF-8 support
config :atml_pdf,
  pdf_backend: AtmlPdf.PdfBackend.ExGutenAdapter
```

**Runtime override** (per-document):

```elixir
# Use PdfAdapter (WinAnsi encoding)
AtmlPdf.render(xml, path, backend: AtmlPdf.PdfBackend.PdfAdapter)

# Use ExGuten (UTF-8 support)
AtmlPdf.render(xml, path, backend: AtmlPdf.PdfBackend.ExGutenAdapter)

# Or when rendering to binary
{:ok, binary} = AtmlPdf.render_binary(xml, backend: AtmlPdf.PdfBackend.ExGutenAdapter)
```

### Character Encoding

The default `PdfAdapter` backend uses the `pdf` library which only supports **WinAnsi encoding** (ASCII + 128 Latin-1 characters). This means:

- ✅ English text: `"Hello World"`
- ✅ Common symbols: `"© ® ™ € £ ¥"`
- ✅ Western European: `"café naïve"`
- ❌ CJK text: `"世界 日本語 한국어"`
- ❌ Emoji: `"🌍 📦 ✈️"`
- ❌ Extended Unicode: `"Здравствуй Καλημέρα"`

**The `ExGutenAdapter` backend supports full UTF-8:**

- ✅ All of the above (English, symbols, Western European)
- ✅ Special characters and symbols: `"✓ ✗ → ←"`
- ✅ Extended Latin characters: `"Müller señor"`
- ✅ CJK characters: `"世界 日本語 한국어"` (with appropriate fonts)
- ✅ Cyrillic and Greek: `"Здравствуй Καλημέρα"`

To use UTF-8 characters, simply configure the ExGuten backend:

```elixir
# In your config
config :atml_pdf, pdf_backend: AtmlPdf.PdfBackend.ExGutenAdapter

# Or per-document
AtmlPdf.render(xml, path, backend: AtmlPdf.PdfBackend.ExGutenAdapter)
```

## API Reference

### `AtmlPdf.render/3`

```elixir
@spec render(String.t(), Path.t(), keyword()) :: :ok | {:error, String.t()}
```

Parses `template`, resolves layout, and writes the PDF to `path`. Returns `:ok`
on success or `{:error, reason}` on failure.

**Options:**
- `:backend` - PDF backend module (defaults to application config or `PdfAdapter`)
- `:compress` - Enable PDF compression (backend-specific)

### `AtmlPdf.render_binary/2`

```elixir
@spec render_binary(String.t(), keyword()) :: {:ok, binary()} | {:error, String.t()}
```

Same as `render/3` but returns `{:ok, binary}` instead of writing to disk.

**Options:**
- `:backend` - PDF backend module (defaults to application config or `PdfAdapter`)
- `:compress` - Enable PDF compression (backend-specific)

## Pipeline Modules

| Module | Responsibility |
|---|---|
| `AtmlPdf.Parser` | Parses ATML XML into `%Document{}` / `%Row{}` / `%Col{}` / `%Img{}` structs |
| `AtmlPdf.Layout` | Resolves `fill`, `fit`, `%`, `pt`, `px` dimensions; propagates font inheritance; applies min/max constraints |
| `AtmlPdf.Renderer` | Walks the resolved tree and issues `Pdf.*` calls to produce a PDF process; handles coordinate-system flip (top-down layout → PDF bottom-left origin) |

## Development

```bash
# Install dependencies
mix deps.get

# Compile
mix compile

# Run tests
mix test

# Run tests with coverage
mix test --cover

# Format
mix format

# Check formatting (CI)
mix format --check-formatted
```

## License

MIT
