defmodule AtmlPdf.ParserTest do
  use ExUnit.Case, async: true

  alias AtmlPdf.Element.{Col, Document, Img, Row}
  alias AtmlPdf.Parser

  # ---------------------------------------------------------------------------
  # parse_dimension/1
  # ---------------------------------------------------------------------------

  describe "parse_dimension/1" do
    test "parses pt value" do
      assert Parser.parse_dimension("100pt") == {:ok, {:pt, 100.0}}
    end

    test "parses px value" do
      assert Parser.parse_dimension("120px") == {:ok, {:px, 120.0}}
    end

    test "parses percentage" do
      assert Parser.parse_dimension("50%") == {:ok, {:percent, 50.0}}
    end

    test "parses fill" do
      assert Parser.parse_dimension("fill") == {:ok, :fill}
    end

    test "parses fit" do
      assert Parser.parse_dimension("fit") == {:ok, :fit}
    end

    test "returns error for unknown format" do
      assert {:error, _} = Parser.parse_dimension("100em")
    end

    test "returns error for bare number" do
      assert {:error, _} = Parser.parse_dimension("100")
    end
  end

  # ---------------------------------------------------------------------------
  # parse_spacing/1
  # ---------------------------------------------------------------------------

  describe "parse_spacing/1" do
    test "single value applies to all sides" do
      assert {:ok, {4.0, 4.0, 4.0, 4.0}} = Parser.parse_spacing("4pt")
    end

    test "two values apply top-bottom and left-right" do
      assert {:ok, {4.0, 8.0, 4.0, 8.0}} = Parser.parse_spacing("4pt 8pt")
    end

    test "four values apply in top right bottom left order" do
      assert {:ok, {1.0, 2.0, 3.0, 4.0}} = Parser.parse_spacing("1pt 2pt 3pt 4pt")
    end

    test "zero shorthand" do
      assert {:ok, {0, 0, 0, 0}} = Parser.parse_spacing("0")
    end

    test "px unit" do
      assert {:ok, {6.0, 6.0, 6.0, 6.0}} = Parser.parse_spacing("6px")
    end
  end

  # ---------------------------------------------------------------------------
  # parse_border/1
  # ---------------------------------------------------------------------------

  describe "parse_border/1" do
    test "none keyword" do
      assert Parser.parse_border("none") == :none
    end

    test "solid border" do
      assert Parser.parse_border("solid 1pt #000000") == {:border, :solid, 1.0, "#000000"}
    end

    test "dashed border" do
      assert Parser.parse_border("dashed 2px #aaaaaa") == {:border, :dashed, 2.0, "#aaaaaa"}
    end

    test "dotted border" do
      assert Parser.parse_border("dotted 0.5pt #cccccc") == {:border, :dotted, 0.5, "#cccccc"}
    end
  end

  # ---------------------------------------------------------------------------
  # Valid XML → Document struct
  # ---------------------------------------------------------------------------

  describe "parse/1 – valid document" do
    test "minimal document with required attributes" do
      xml = ~s|<document width="400pt" height="600pt"></document>|
      assert {:ok, %Document{width: {:pt, 400.0}, height: {:pt, 600.0}}} = Parser.parse(xml)
    end

    test "document font defaults" do
      xml = ~s|<document width="10pt" height="10pt"></document>|
      assert {:ok, doc} = Parser.parse(xml)
      assert doc.font_family == "Helvetica"
      assert doc.font_size == 8.0
      assert doc.font_weight == :normal
    end

    test "document explicit font attributes" do
      xml =
        ~s|<document width="10pt" height="10pt" font-family="Arial" font-size="12pt" font-weight="bold"></document>|

      assert {:ok, doc} = Parser.parse(xml)
      assert doc.font_family == "Arial"
      assert doc.font_size == 12.0
      assert doc.font_weight == :bold
    end

    test "document padding shorthand" do
      xml = ~s|<document width="10pt" height="10pt" padding="4pt"></document>|
      assert {:ok, doc} = Parser.parse(xml)
      assert doc.padding == {4.0, 4.0, 4.0, 4.0}
    end

    test "document with a row child" do
      xml = ~s|<document width="10pt" height="10pt"><row></row></document>|
      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{}] = doc.children
    end

    test "row with col child" do
      xml = ~s|<document width="10pt" height="10pt"><row><col>hello</col></row></document>|
      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{children: [%Col{children: ["hello"]}]}] = doc.children
    end

    test "row default dimensions" do
      xml = ~s|<document width="10pt" height="10pt"><row></row></document>|
      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{height: :fit, width: :fill}] = doc.children
    end

    test "row explicit height fill" do
      xml = ~s|<document width="10pt" height="10pt"><row height="fill"></row></document>|
      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{height: :fill}] = doc.children
    end

    test "row explicit height in pt" do
      xml = ~s|<document width="10pt" height="10pt"><row height="60pt"></row></document>|
      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{height: {:pt, 60.0}}] = doc.children
    end

    test "row border-bottom shorthand" do
      xml =
        ~s|<document width="10pt" height="10pt"><row border-bottom="solid 1pt #000000"></row></document>|

      assert {:ok, doc} = Parser.parse(xml)

      assert [%Row{border_bottom: {:border, :solid, 1.0, "#000000"}, border_top: :none}] =
               doc.children
    end

    test "row border shorthand applies to all sides, per-side overrides" do
      xml = """
      <document width="10pt" height="10pt">
        <row border="solid 1pt #000000" border-top="none"></row>
      </document>
      """

      assert {:ok, doc} = Parser.parse(xml)
      assert [row] = doc.children
      assert row.border_top == :none
      assert row.border_right == {:border, :solid, 1.0, "#000000"}
      assert row.border_bottom == {:border, :solid, 1.0, "#000000"}
      assert row.border_left == {:border, :solid, 1.0, "#000000"}
    end

    test "col default dimensions" do
      xml = ~s|<document width="10pt" height="10pt"><row><col></col></row></document>|
      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{children: [%Col{width: :fill, height: :fill}]}] = doc.children
    end

    test "col explicit width percentage" do
      xml = ~s|<document width="10pt" height="10pt"><row><col width="50%"></col></row></document>|
      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{children: [%Col{width: {:percent, 50.0}}]}] = doc.children
    end

    test "col text-align and vertical-align" do
      xml = """
      <document width="10pt" height="10pt">
        <row><col text-align="center" vertical-align="bottom"></col></row>
      </document>
      """

      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{children: [%Col{text_align: :center, vertical_align: :bottom}]}] = doc.children
    end

    test "col font override" do
      xml = """
      <document width="10pt" height="10pt">
        <row><col font-size="14pt" font-weight="bold"></col></row>
      </document>
      """

      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{children: [%Col{font_size: 14.0, font_weight: :bold}]}] = doc.children
    end

    test "col nil font fields when not specified (inheritable)" do
      xml = ~s|<document width="10pt" height="10pt"><row><col></col></row></document>|
      assert {:ok, doc} = Parser.parse(xml)

      assert [%Row{children: [%Col{font_family: nil, font_size: nil, font_weight: nil}]}] =
               doc.children
    end

    test "col padding per-side override" do
      xml = """
      <document width="10pt" height="10pt">
        <row><col padding="4pt" padding-top="8pt"></col></row>
      </document>
      """

      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{children: [%Col{padding_top: 8.0, padding_right: 4.0}]}] = doc.children
    end

    test "img with src" do
      xml = """
      <document width="10pt" height="10pt">
        <row><col><img src="/logo.png" width="60pt" height="40pt" /></col></row>
      </document>
      """

      assert {:ok, doc} = Parser.parse(xml)

      assert [
               %Row{
                 children: [
                   %Col{
                     children: [%Img{src: "/logo.png", width: {:pt, 60.0}, height: {:pt, 40.0}}]
                   }
                 ]
               }
             ] =
               doc.children
    end

    test "img defaults to fit dimensions" do
      xml = """
      <document width="10pt" height="10pt">
        <row><col><img src="base64:abc" /></col></row>
      </document>
      """

      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{children: [%Col{children: [%Img{width: :fit, height: :fit}]}]}] = doc.children
    end

    test "col min-width and max-width" do
      xml = """
      <document width="10pt" height="10pt">
        <row><col min-width="20pt" max-width="100pt"></col></row>
      </document>
      """

      assert {:ok, doc} = Parser.parse(xml)

      assert [%Row{children: [%Col{min_width: {:pt, 20.0}, max_width: {:pt, 100.0}}]}] =
               doc.children
    end

    test "nested row inside col" do
      xml = """
      <document width="10pt" height="10pt">
        <row>
          <col>
            <row><col>inner</col></row>
          </col>
        </row>
      </document>
      """

      assert {:ok, doc} = Parser.parse(xml)

      assert [%Row{children: [%Col{children: [%Row{children: [%Col{children: ["inner"]}]}]}]}] =
               doc.children
    end

    test "whitespace-only text nodes are dropped" do
      xml = """
      <document width="10pt" height="10pt">
        <row>
          <col>  </col>
        </row>
      </document>
      """

      assert {:ok, doc} = Parser.parse(xml)
      assert [%Row{children: [%Col{children: []}]}] = doc.children
    end
  end

  # ---------------------------------------------------------------------------
  # Nesting violations
  # ---------------------------------------------------------------------------

  describe "parse/1 – nesting violations" do
    test "returns error when root element is not document" do
      xml = ~s|<row height="10pt"></row>|
      assert {:error, msg} = Parser.parse(xml)
      assert msg =~ "document"
    end

    test "returns error for non-row child of document" do
      xml = ~s|<document width="10pt" height="10pt"><col></col></document>|
      assert {:error, msg} = Parser.parse(xml)
      assert msg =~ "<col>"
    end

    test "returns error for non-col child of row" do
      xml = ~s|<document width="10pt" height="10pt"><row><img src="x" /></row></document>|
      assert {:error, msg} = Parser.parse(xml)
      assert msg =~ "<img>"
    end

    test "returns error for col directly inside col" do
      xml = """
      <document width="10pt" height="10pt">
        <row><col><col></col></col></row>
      </document>
      """

      assert {:error, msg} = Parser.parse(xml)
      assert msg =~ "<col>"
    end
  end

  # ---------------------------------------------------------------------------
  # Missing required attributes
  # ---------------------------------------------------------------------------

  describe "parse/1 – missing required attributes" do
    test "missing document width" do
      xml = ~s|<document height="10pt"></document>|
      assert {:error, msg} = Parser.parse(xml)
      assert msg =~ "width"
    end

    test "missing document height" do
      xml = ~s|<document width="10pt"></document>|
      assert {:error, msg} = Parser.parse(xml)
      assert msg =~ "height"
    end

    test "missing img src" do
      xml = ~s|<document width="10pt" height="10pt"><row><col><img /></col></row></document>|
      assert {:error, msg} = Parser.parse(xml)
      assert msg =~ "src"
    end
  end

  # ---------------------------------------------------------------------------
  # Malformed XML
  # ---------------------------------------------------------------------------

  describe "parse/1 – malformed XML" do
    test "returns error for non-XML input" do
      assert {:error, _} = Parser.parse("not xml at all")
    end
  end
end
