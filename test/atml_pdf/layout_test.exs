defmodule AtmlPdf.LayoutTest do
  use ExUnit.Case, async: true

  alias AtmlPdf.Element.{Col, Document, Row}
  alias AtmlPdf.Layout
  alias AtmlPdf.Parser

  # Helper: parse XML then resolve layout, raising on any error.
  defp resolve!(xml) do
    {:ok, parsed} = Parser.parse(xml)
    {:ok, resolved} = Layout.resolve(parsed)
    resolved
  end

  # ---------------------------------------------------------------------------
  # resolve/1 – document dimensions
  # ---------------------------------------------------------------------------

  describe "resolve/1 – document dimensions" do
    test "pt dimensions are converted to floats" do
      doc = resolve!(~s|<document width="400pt" height="600pt"></document>|)
      assert doc.width == 400.0
      assert doc.height == 600.0
    end

    test "px dimensions are converted to pt (1px = 0.75pt)" do
      doc = resolve!(~s|<document width="400px" height="600px"></document>|)
      assert doc.width == 300.0
      assert doc.height == 450.0
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/1 – font inheritance
  # ---------------------------------------------------------------------------

  describe "resolve/1 – font inheritance" do
    test "document font defaults propagate to col when col sets nothing" do
      doc =
        resolve!("""
        <document width="100pt" height="100pt"
                  font-family="Helvetica" font-size="8pt" font-weight="normal">
          <row><col></col></row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert col.font_family == "Helvetica"
      assert col.font_size == 8.0
      assert col.font_weight == :normal
    end

    test "col overrides font-size, inherits the rest" do
      doc =
        resolve!("""
        <document width="100pt" height="100pt"
                  font-family="Courier" font-size="8pt" font-weight="normal">
          <row><col font-size="14pt"></col></row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert col.font_family == "Courier"
      assert col.font_size == 14.0
      assert col.font_weight == :normal
    end

    test "col overrides font-weight, inherits font-family and font-size" do
      doc =
        resolve!("""
        <document width="100pt" height="100pt"
                  font-family="Arial" font-size="10pt" font-weight="normal">
          <row><col font-weight="bold"></col></row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert col.font_family == "Arial"
      assert col.font_size == 10.0
      assert col.font_weight == :bold
    end

    test "col overrides all three font attrs" do
      doc =
        resolve!("""
        <document width="100pt" height="100pt"
                  font-family="Helvetica" font-size="8pt" font-weight="normal">
          <row><col font-family="Times" font-size="12pt" font-weight="bold"></col></row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert col.font_family == "Times"
      assert col.font_size == 12.0
      assert col.font_weight == :bold
    end

    test "font inheritance cascades through nested rows into inner cols" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt" font-family="Helvetica" font-size="8pt">
          <row>
            <col font-size="12pt">
              <row><col font-weight="bold"></col></row>
            </col>
          </row>
        </document>
        """)

      [%Row{children: [outer_col]}] = doc.children
      assert outer_col.font_size == 12.0

      [%Row{children: [inner_col]}] = outer_col.children
      # inherits font-size 12pt from outer col, overrides font-weight
      assert inner_col.font_family == "Helvetica"
      assert inner_col.font_size == 12.0
      assert inner_col.font_weight == :bold
    end

    test "sibling cols can have different font overrides independently" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt" font-family="Helvetica" font-size="8pt">
          <row>
            <col font-size="10pt"></col>
            <col font-weight="bold"></col>
          </row>
        </document>
        """)

      [%Row{children: [col_a, col_b]}] = doc.children
      assert col_a.font_size == 10.0
      assert col_a.font_weight == :normal

      assert col_b.font_size == 8.0
      assert col_b.font_weight == :bold
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/1 – fixed dimensions (pt / px / %)
  # ---------------------------------------------------------------------------

  describe "resolve/1 – fixed dimensions" do
    test "row with fixed pt height" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="60pt"></row>
        </document>
        """)

      [row] = doc.children
      assert row.height == 60.0
    end

    test "row width defaults to fill (equals document width)" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="20pt"></row>
        </document>
        """)

      [row] = doc.children
      assert row.width == 100.0
    end

    test "col with fixed pt width" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt"><col width="80pt"></col></row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert col.width == 80.0
    end

    test "col with px width is converted to pt" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt"><col width="80px"></col></row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert col.width == 60.0
    end

    test "col with percentage width resolves relative to row width" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt">
            <col width="50%"></col>
            <col width="50%"></col>
          </row>
        </document>
        """)

      [%Row{children: [col_a, col_b]}] = doc.children
      assert col_a.width == 100.0
      assert col_b.width == 100.0
    end

    test "col with 33% width resolves correctly" do
      doc =
        resolve!("""
        <document width="300pt" height="100pt">
          <row height="40pt"><col width="33%"></col></row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert_in_delta col.width, 99.0, 0.01
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/1 – fill distribution
  # ---------------------------------------------------------------------------

  describe "resolve/1 – fill distribution" do
    test "single fill col consumes entire row width" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt"><col width="fill"></col></row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert col.width == 200.0
    end

    test "two fill cols share row width equally" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt">
            <col width="fill"></col>
            <col width="fill"></col>
          </row>
        </document>
        """)

      [%Row{children: [col_a, col_b]}] = doc.children
      assert col_a.width == 100.0
      assert col_b.width == 100.0
    end

    test "fill col takes remaining width after fixed col" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt">
            <col width="80pt"></col>
            <col width="fill"></col>
          </row>
        </document>
        """)

      [%Row{children: [fixed_col, fill_col]}] = doc.children
      assert fixed_col.width == 80.0
      assert fill_col.width == 120.0
    end

    test "three fill cols share remaining space after fixed col" do
      doc =
        resolve!("""
        <document width="300pt" height="100pt">
          <row height="40pt">
            <col width="60pt"></col>
            <col width="fill"></col>
            <col width="fill"></col>
            <col width="fill"></col>
          </row>
        </document>
        """)

      [%Row{children: [_fixed, fill_a, fill_b, fill_c]}] = doc.children
      assert fill_a.width == 80.0
      assert fill_b.width == 80.0
      assert fill_c.width == 80.0
    end

    test "single fill row consumes entire document height" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="fill"><col></col></row>
        </document>
        """)

      [row] = doc.children
      assert row.height == 200.0
    end

    test "two fill rows share document height equally" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="fill"><col></col></row>
          <row height="fill"><col></col></row>
        </document>
        """)

      [row_a, row_b] = doc.children
      assert row_a.height == 100.0
      assert row_b.height == 100.0
    end

    test "fill row takes remaining height after fixed row" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="60pt"><col></col></row>
          <row height="fill"><col></col></row>
        </document>
        """)

      [fixed_row, fill_row] = doc.children
      assert fixed_row.height == 60.0
      assert fill_row.height == 140.0
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/1 – fit (content-sized)
  # ---------------------------------------------------------------------------

  describe "resolve/1 – fit dimensions" do
    test "fit row height is non-negative" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="fit"><col>hello</col></row>
        </document>
        """)

      [row] = doc.children
      assert row.height >= 0.0
    end

    test "fit row with text content has positive height" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt" font-size="10pt">
          <row height="fit"><col>hello world</col></row>
        </document>
        """)

      [row] = doc.children
      assert row.height > 0.0
    end

    test "empty fit row has zero height" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="fit"><col></col></row>
        </document>
        """)

      [row] = doc.children
      assert row.height == 0.0
    end

    test "fit col height fills its row by default" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="50pt"><col height="fill"></col></row>
        </document>
        """)

      [%Row{height: rh, children: [col]}] = doc.children
      assert rh == 50.0
      assert col.height == 50.0
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/1 – min/max constraints
  # ---------------------------------------------------------------------------

  describe "resolve/1 – min/max constraints" do
    test "min-height is applied as a floor on a fixed row" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="20pt" min-height="40pt"><col></col></row>
        </document>
        """)

      [row] = doc.children
      assert row.height == 40.0
    end

    test "max-height is applied as a ceiling on a fixed row" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="80pt" max-height="50pt"><col></col></row>
        </document>
        """)

      [row] = doc.children
      assert row.height == 50.0
    end

    test "row height within min/max range is unchanged" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="40pt" min-height="20pt" max-height="60pt"><col></col></row>
        </document>
        """)

      [row] = doc.children
      assert row.height == 40.0
    end

    test "min-width is applied as a floor on a col" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt">
            <col width="30pt" min-width="60pt"></col>
          </row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert col.width == 60.0
    end

    test "max-width is applied as a ceiling on a col" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt">
            <col width="100pt" max-width="50pt"></col>
          </row>
        </document>
        """)

      [%Row{children: [col]}] = doc.children
      assert col.width == 50.0
    end

    test "min-width on fill col constrains fill distribution" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt">
            <col width="fill" min-width="120pt"></col>
            <col width="fill"></col>
          </row>
        </document>
        """)

      [%Row{children: [col_a, col_b]}] = doc.children
      # col_a fill share = 100pt, but min-width forces it to 120pt
      assert col_a.width == 120.0
      # col_b fill share = 100pt, no constraint
      assert col_b.width == 100.0
    end

    test "max-width on fill col constrains fill distribution" do
      doc =
        resolve!("""
        <document width="200pt" height="100pt">
          <row height="40pt">
            <col width="fill" max-width="60pt"></col>
            <col width="fill"></col>
          </row>
        </document>
        """)

      [%Row{children: [col_a, col_b]}] = doc.children
      # Each fill share = 100pt; col_a is capped at 60pt
      assert col_a.width == 60.0
      assert col_b.width == 100.0
    end

    test "min and max constraints are cleared after resolution" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="40pt" min-height="10pt" max-height="80pt">
            <col min-width="5pt" max-width="200pt"></col>
          </row>
        </document>
        """)

      [%Row{min_height: min_h, max_height: max_h, children: [col]}] = doc.children
      assert min_h == nil
      assert max_h == nil
      assert col.min_width == nil
      assert col.max_width == nil
    end

    test "min-height with % is resolved relative to parent height" do
      doc =
        resolve!("""
        <document width="100pt" height="200pt">
          <row height="40pt" min-height="50%"><col></col></row>
        </document>
        """)

      [row] = doc.children
      # min-height 50% of parent (200pt) = 100pt > base 40pt → clamped to 100pt
      assert row.height == 100.0
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/1 – image resolution
  # ---------------------------------------------------------------------------

  describe "resolve/1 – image resolution" do
    test "img with fixed pt dimensions resolves to floats" do
      doc =
        resolve!("""
        <document width="200pt" height="200pt">
          <row height="80pt">
            <col><img src="/logo.png" width="60pt" height="40pt" /></col>
          </row>
        </document>
        """)

      [%Row{children: [%Col{children: [img]}]}] = doc.children
      assert img.width == 60.0
      assert img.height == 40.0
    end

    test "img with fit dimensions resolves to 0.0" do
      doc =
        resolve!("""
        <document width="200pt" height="200pt">
          <row height="80pt">
            <col><img src="base64:abc" /></col>
          </row>
        </document>
        """)

      [%Row{children: [%Col{children: [img]}]}] = doc.children
      assert img.width == 0.0
      assert img.height == 0.0
    end

    test "img with fill width fills parent col width" do
      doc =
        resolve!("""
        <document width="200pt" height="200pt">
          <row height="80pt">
            <col width="120pt"><img src="/bar.png" width="fill" height="40pt" /></col>
          </row>
        </document>
        """)

      [%Row{children: [%Col{children: [img]}]}] = doc.children
      assert img.width == 120.0
    end

    test "img min/max constraints are cleared after resolution" do
      doc =
        resolve!("""
        <document width="200pt" height="200pt">
          <row height="80pt">
            <col>
              <img src="/logo.png" width="60pt" height="40pt"
                   min-width="10pt" max-width="80pt"
                   min-height="10pt" max-height="60pt" />
            </col>
          </row>
        </document>
        """)

      [%Row{children: [%Col{children: [img]}]}] = doc.children
      assert img.min_width == nil
      assert img.max_width == nil
      assert img.min_height == nil
      assert img.max_height == nil
    end
  end

  # ---------------------------------------------------------------------------
  # resolve/1 – output shape invariants
  # ---------------------------------------------------------------------------

  describe "resolve/1 – output shape" do
    test "all dimension fields in resolved tree are plain floats" do
      doc =
        resolve!("""
        <document width="400pt" height="600pt">
          <row height="60pt">
            <col width="80pt"></col>
            <col width="fill"></col>
          </row>
          <row height="fill">
            <col width="50%">
              <row height="fit"><col>text</col></row>
            </col>
            <col width="fill"></col>
          </row>
        </document>
        """)

      assert is_float(doc.width)
      assert is_float(doc.height)

      Enum.each(doc.children, fn %Row{} = row ->
        assert is_float(row.width)
        assert is_float(row.height)

        Enum.each(row.children, fn %Col{} = col ->
          assert is_float(col.width)
          assert is_float(col.height)
        end)
      end)
    end

    test "all col font fields are resolved (non-nil) after layout" do
      doc =
        resolve!("""
        <document width="100pt" height="100pt" font-family="Helvetica" font-size="9pt">
          <row height="20pt">
            <col></col>
            <col font-size="11pt" font-weight="bold"></col>
          </row>
        </document>
        """)

      [%Row{children: [col_a, col_b]}] = doc.children
      assert is_binary(col_a.font_family)
      assert is_number(col_a.font_size)
      assert col_a.font_weight in [:normal, :bold]

      assert is_binary(col_b.font_family)
      assert is_number(col_b.font_size)
      assert col_b.font_weight in [:normal, :bold]
    end

    test "resolve/1 returns error tuple for non-Document input" do
      assert {:error, _} = Layout.resolve(%Document{width: nil, height: nil})
    end
  end
end
