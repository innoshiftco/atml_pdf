# Implementation Plan — atml_pdf

Render PDF files from ATML templates via a simple two-function public API.

## Public API (AtmlPdf)

```elixir
AtmlPdf.render(template_string, target_file_path, opts \\ [])
# → :ok | {:error, reason}

AtmlPdf.render_binary(template_string, opts \\ [])
# → {:ok, binary} | {:error, reason}
```

---

## Pipeline

```
ATML XML string
  → AtmlPdf.Parser     (XML → element structs)
  → AtmlPdf.Layout     (resolve dimensions, apply inheritance)
  → AtmlPdf.Renderer   (element tree → PDF bytes via the `pdf` lib)
```

---

## Phase 1 — Element Structs (`lib/atml_pdf/element/`)

Plain data structs — no logic, just shape. One module per element.

| Module | Key Fields |
|--------|-----------|
| `AtmlPdf.Element.Document` | `width, height, padding, font_family, font_size, font_weight, children` |
| `AtmlPdf.Element.Row` | `height, min_height, max_height, width, padding_top/right/bottom/left, border_*, vertical_align, children` |
| `AtmlPdf.Element.Col` | `width, min_width, max_width, height, padding_*, border_*, font_family, font_size, font_weight, text_align, vertical_align, children` |
| `AtmlPdf.Element.Img` | `src, width, height, min_width, max_width, min_height, max_height` |

Files:
- `lib/atml_pdf/element/document.ex`
- `lib/atml_pdf/element/row.ex`
- `lib/atml_pdf/element/col.ex`
- `lib/atml_pdf/element/img.ex`

---

## Phase 2 — Parser (`lib/atml_pdf/parser.ex`)

Parses ATML XML into element structs using `sweet_xml`.

- `SweetXml.parse/1` handles the raw XML → xmerl node tree; no need to write
  XML parsing from scratch.
- Walk the xmerl node tree using `SweetXml.xpath/2` with `~x` sigils to extract
  element names, attributes, and children.
- Validate nesting rules (see spec): `<document>` → `<row>` → `<col>` → text/`<img>`/`<row>`.
- Return `{:ok, %AtmlPdf.Element.Document{}}` or `{:error, reason}`.
- Implement attribute value parsers (pure string → typed value functions):
  - **Dimension:** `100pt` | `120px` | `50%` | `fill` | `fit`
  - **Spacing:** single / two / four value shorthand (`4pt`, `4pt 8pt`, `2pt 4pt 2pt 4pt`)
  - **Border:** `none` or `"<style> <width> <color>"` (`solid 1pt #000000`)
  - **Font:** `font-family` (string), `font-size` (`<n>pt`), `font-weight` (`normal` | `bold`)
  - **Alignment:** `text-align`, `vertical-align`

---

## Phase 3 — Layout (`lib/atml_pdf/layout.ex`)

Resolves the parsed element tree into concrete point values.

- Propagate font inheritance top-down: `<document>` → `<row>` → `<col>`.
  - Non-font attributes (padding, border, alignment) do NOT inherit.
- Resolve `%` relative to parent computed dimension.
- Resolve `fit` by measuring content size (text height / image intrinsic size).
- Resolve `fill` by distributing remaining space equally among `fill` siblings,
  after all fixed and `fit` siblings are resolved.
- Apply constraints in order:
  1. Compute base value (`%`, `fill`, `fit`)
  2. Apply `min-*` as floor
  3. Apply `max-*` as ceiling
- Return a fully-resolved element tree where every dimension is a plain number (pt).

---

## Phase 4 — Renderer (`lib/atml_pdf/renderer.ex`)

Walks the resolved element tree and issues `Pdf.*` calls.

- Create a `Pdf` document with custom `[size: [width, height]]` from `<document>`.
- **Coordinate system:** `pdf` lib uses bottom-left origin; renderer must flip the
  Y-axis (`pdf_y = page_height - layout_y - element_height`).
- For each element:
  - **Borders** → `Pdf.set_stroke_color` + `Pdf.set_line_width` + `Pdf.line` (per side)
  - **Text** → `Pdf.set_font` + `Pdf.text_wrap` with `:align` option for `text-align`;
    `vertical-align` adjusts the Y coordinate within the cell.
  - **Images** → `Pdf.add_image`; if `src` starts with `base64:`, decode and write to
    a temp file first, clean up after.
- Return `{:ok, pdf_pid}` or `{:error, reason}`.

---

## Phase 5 — Public API (`lib/atml_pdf.ex`)

Thin orchestrator: `Parser → Layout → Renderer → output`.

```elixir
def render(template, path, opts \\ []) do
  with {:ok, tree}     <- Parser.parse(template),
       {:ok, resolved} <- Layout.resolve(tree),
       {:ok, pdf}      <- Renderer.render(resolved, opts) do
    Pdf.write_to(pdf, path)
    Pdf.cleanup(pdf)
    :ok
  end
end

def render_binary(template, opts \\ []) do
  with {:ok, tree}     <- Parser.parse(template),
       {:ok, resolved} <- Layout.resolve(tree),
       {:ok, pdf}      <- Renderer.render(resolved, opts) do
    binary = Pdf.export(pdf)
    Pdf.cleanup(pdf)
    {:ok, binary}
  end
end
```

---

## Phase 6 — Tests

| File | Coverage |
|------|---------|
| `test/atml_pdf/element/document_test.exs` | Struct defaults |
| `test/atml_pdf/parser_test.exs` | Valid XML, nesting violations, each value type, missing required attrs |
| `test/atml_pdf/layout_test.exs` | `fill`/`fit`/`%` resolution, font inheritance, min/max constraints |
| `test/atml_pdf/renderer_test.exs` | Smoke test: full example template produces non-empty binary |
| `test/atml_pdf_test.exs` | End-to-end: `render_binary/2` on the full spec example |

---

## File Tree (target state)

```
lib/
  atml_pdf.ex                        # Public API
  atml_pdf/
    parser.ex                        # Phase 2
    layout.ex                        # Phase 3
    renderer.ex                      # Phase 4
    element/
      document.ex                    # Phase 1
      row.ex                         # Phase 1
      col.ex                         # Phase 1
      img.ex                         # Phase 1

test/
  atml_pdf_test.exs                  # End-to-end
  atml_pdf/
    parser_test.exs
    layout_test.exs
    renderer_test.exs
    element/
      document_test.exs
```
