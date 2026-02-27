# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-27

### Added

- **Core PDF rendering pipeline** with three-stage architecture:
  - `AtmlPdf.Parser` - Parses ATML XML into element structs
  - `AtmlPdf.Layout` - Resolves dimensions, font inheritance, and constraints
  - `AtmlPdf.Renderer` - Generates PDF output via pluggable backends

- **ATML language support** for declarative label layouts:
  - Document structure with nested rows and columns
  - Multiple dimension units: points (`pt`), pixels (`px`), percentages (`%`), `fill`, and `fit`
  - Flexible padding system (per-side and shorthand notation)
  - Border styling (solid, dashed, dotted) with configurable width and color
  - Font inheritance with `font-family`, `font-size`, and `font-weight` attributes
  - Text alignment (`text-align`, `vertical-align`)
  - Image support with file paths, data URIs, and legacy base64 format
  - Automatic proportional scaling for images

- **Pluggable PDF backend system**:
  - `PdfAdapter` - Default backend using the `pdf` library (WinAnsi encoding, ASCII + Latin-1)
  - `ExGutenAdapter` - UTF-8 backend with full Unicode support (Vietnamese, Thai, CJK, Cyrillic, Greek, emoji)
  - Runtime backend selection per document or application-wide configuration
  - Automatic TTF font registration from `priv/fonts/` directory
  - Configurable font registration for custom font locations
  - Automatic fallback font chain for missing glyphs

- **Mix task** for command-line rendering:
  - `mix atml_pdf.render` - Render ATML templates to PDF without writing code
  - Support for explicit output paths
  - `--backend` flag for choosing PDF backend
  - Exit code feedback (0 = success, 1 = error)

- **Public API**:
  - `AtmlPdf.render/3` - Parse and render to file
  - `AtmlPdf.render_binary/2` - Parse and render to binary
  - Backend and compression options

- **Documentation**:
  - Comprehensive README with language reference
  - API documentation with examples
  - Barcode generation guide using Barlix
  - Backend configuration guide
  - Development setup instructions

- **Bundled fonts**:
  - NotoSans (Regular) - Latin, Vietnamese, extended Latin coverage
  - NotoSansThai (Regular) - Thai script coverage

### Changed

- **Terminology cleanup**: Removed all "Airway Bill" / "AWB" references in favor of generic "label" terminology

[1.0.0]: https://github.com/innoshiftco/atml_pdf/releases/tag/v1.0.0
