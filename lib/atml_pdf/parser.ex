defmodule AtmlPdf.Parser do
  @moduledoc """
  Parses an ATML XML string into an `AtmlPdf.Element.Document` struct tree.

  ## Pipeline

      AtmlPdf.Parser.parse(xml_string)
      # → {:ok, %AtmlPdf.Element.Document{}}
      # → {:error, reason}

  Internally this module:

  1. Delegates raw XML → xmerl node tree to `SweetXml.parse/1`.
  2. Walks the xmerl tree recursively, building element structs.
  3. Validates nesting rules during the walk.
  4. Converts attribute strings to typed values (dimension, spacing, border, etc.).
  """

  alias AtmlPdf.Element.{Col, Document, Img, Row}

  @type parse_result :: {:ok, Document.t()} | {:error, String.t()}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Parses an ATML XML string and returns an element struct tree.

  ## Examples

      iex> xml = ~s|<document width="100pt" height="200pt"></document>|
      iex> {:ok, doc} = AtmlPdf.Parser.parse(xml)
      iex> doc.width
      {:pt, 100.0}
      iex> doc.height
      {:pt, 200.0}

  """
  @spec parse(String.t()) :: parse_result()
  def parse(xml) when is_binary(xml) do
    xmerl = SweetXml.parse(xml)
    build_document(xmerl)
  rescue
    e -> {:error, "XML parse error: #{Exception.message(e)}"}
  catch
    :exit, reason -> {:error, "XML parse error: #{inspect(reason)}"}
  end

  # ---------------------------------------------------------------------------
  # Document
  # ---------------------------------------------------------------------------

  defp build_document({:xmlElement, :document, _, _, _, _, _, attrs, children, _, _, _}) do
    with {:ok, width} <- require_attr(attrs, "width", &parse_dimension/1),
         {:ok, height} <- require_attr(attrs, "height", &parse_dimension/1) do
      padding = get_padding(attrs)

      doc = %Document{
        width: width,
        height: height,
        padding: padding,
        font_family: get_attr(attrs, "font-family", "Helvetica"),
        font_size: parse_font_size_value(get_attr(attrs, "font-size", "8pt")),
        font_weight: parse_font_weight_value(get_attr(attrs, "font-weight", "normal")),
        children: []
      }

      with {:ok, row_children} <- build_children(children, :document, doc) do
        {:ok, %{doc | children: row_children}}
      end
    end
  end

  defp build_document({:xmlElement, name, _, _, _, _, _, _, _, _, _, _}) do
    {:error, "Root element must be <document>, got <#{name}>"}
  end

  defp build_document(_) do
    {:error, "Expected an XML element at document root"}
  end

  # ---------------------------------------------------------------------------
  # Row
  # ---------------------------------------------------------------------------

  defp build_row({:xmlElement, :row, _, _, _, _, _, attrs, children, _, _, _}, _parent_ctx) do
    row = %Row{
      height: get_dimension_attr(attrs, "height", :fit),
      min_height: get_optional_dimension_attr(attrs, "min-height"),
      max_height: get_optional_dimension_attr(attrs, "max-height"),
      width: get_dimension_attr(attrs, "width", :fill),
      border_top: get_border_side(attrs, "border", "border-top"),
      border_right: get_border_side(attrs, "border", "border-right"),
      border_bottom: get_border_side(attrs, "border", "border-bottom"),
      border_left: get_border_side(attrs, "border", "border-left"),
      vertical_align: parse_vertical_align_value(get_attr(attrs, "vertical-align", "top")),
      children: []
    }

    {pt, pr, pb, pl} = get_padding(attrs)

    row = %{
      row
      | padding_top: pt,
        padding_right: pr,
        padding_bottom: pb,
        padding_left: pl
    }

    with {:ok, col_children} <- build_children(children, :row, row) do
      {:ok, %{row | children: col_children}}
    end
  end

  # ---------------------------------------------------------------------------
  # Col
  # ---------------------------------------------------------------------------

  defp build_col({:xmlElement, :col, _, _, _, _, _, attrs, children, _, _, _}, _parent_ctx) do
    col = %Col{
      width: get_dimension_attr(attrs, "width", :fill),
      min_width: get_optional_dimension_attr(attrs, "min-width"),
      max_width: get_optional_dimension_attr(attrs, "max-width"),
      height: get_dimension_attr(attrs, "height", :fill),
      border_top: get_border_side(attrs, "border", "border-top"),
      border_right: get_border_side(attrs, "border", "border-right"),
      border_bottom: get_border_side(attrs, "border", "border-bottom"),
      border_left: get_border_side(attrs, "border", "border-left"),
      font_family: get_optional_attr(attrs, "font-family"),
      font_size: get_optional_font_size(attrs, "font-size"),
      font_weight: get_optional_font_weight(attrs, "font-weight"),
      text_align: parse_text_align_value(get_attr(attrs, "text-align", "left")),
      vertical_align: parse_vertical_align_value(get_attr(attrs, "vertical-align", "top")),
      children: []
    }

    {pt, pr, pb, pl} = get_padding(attrs)

    col = %{
      col
      | padding_top: pt,
        padding_right: pr,
        padding_bottom: pb,
        padding_left: pl
    }

    with {:ok, col_children} <- build_children(children, :col, col) do
      {:ok, %{col | children: col_children}}
    end
  end

  # ---------------------------------------------------------------------------
  # Img
  # ---------------------------------------------------------------------------

  defp build_img({:xmlElement, :img, _, _, _, _, _, attrs, _, _, _, _}) do
    with {:ok, src} <- require_string_attr(attrs, "src") do
      img = %Img{
        src: src,
        width: get_dimension_attr(attrs, "width", :fit),
        height: get_dimension_attr(attrs, "height", :fit),
        min_width: get_optional_dimension_attr(attrs, "min-width"),
        max_width: get_optional_dimension_attr(attrs, "max-width"),
        min_height: get_optional_dimension_attr(attrs, "min-height"),
        max_height: get_optional_dimension_attr(attrs, "max-height")
      }

      {:ok, img}
    end
  end

  # ---------------------------------------------------------------------------
  # Child dispatch / nesting validation
  # ---------------------------------------------------------------------------

  # Returns {:ok, [element | text_string]} for the children of a node.
  # `parent_tag` is :document | :row | :col to enforce nesting rules.
  defp build_children(children, parent_tag, _parent_struct) do
    children
    |> Enum.reduce_while({:ok, []}, fn child, {:ok, acc} ->
      case build_child(child, parent_tag) do
        {:ok, nil} ->
          {:cont, {:ok, acc}}

        {:ok, built} ->
          # Prepend for O(n) accumulation; reverse once at the end.
          {:cont, {:ok, [built | acc]}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      other -> other
    end
  end

  # Whitespace-only text nodes are silently dropped.
  defp build_child({:xmlText, _, _, _, text, :text}, _parent_tag) do
    str = text |> List.to_string() |> String.trim()
    if str == "", do: {:ok, nil}, else: {:ok, str}
  end

  # <document> may only contain <row>
  defp build_child({:xmlElement, :row, _, _, _, _, _, _, _, _, _, _} = node, :document) do
    build_row(node, :document)
  end

  defp build_child({:xmlElement, name, _, _, _, _, _, _, _, _, _, _}, :document)
       when name != :row do
    {:error, "<document> may only contain <row> children, got <#{name}>"}
  end

  # <row> may only contain <col>
  defp build_child({:xmlElement, :col, _, _, _, _, _, _, _, _, _, _} = node, :row) do
    build_col(node, :row)
  end

  defp build_child({:xmlElement, name, _, _, _, _, _, _, _, _, _, _}, :row)
       when name != :col do
    {:error, "<row> may only contain <col> children, got <#{name}>"}
  end

  # <col> may contain text (handled above), <img>, or <row>. Not <col>.
  defp build_child({:xmlElement, :img, _, _, _, _, _, _, _, _, _, _} = node, :col) do
    build_img(node)
  end

  defp build_child({:xmlElement, :row, _, _, _, _, _, _, _, _, _, _} = node, :col) do
    build_row(node, :col)
  end

  defp build_child({:xmlElement, :col, _, _, _, _, _, _, _, _, _, _}, :col) do
    {:error, "<col> cannot be a direct child of another <col>"}
  end

  defp build_child({:xmlElement, name, _, _, _, _, _, _, _, _, _, _}, :col) do
    {:error, "<col> may not contain <#{name}>"}
  end

  # Ignore XML comments and processing instructions
  defp build_child({tag, _, _, _, _, _}, _parent) when tag in [:xmlComment, :xmlPI] do
    {:ok, nil}
  end

  defp build_child(_node, _parent), do: {:ok, nil}

  # ---------------------------------------------------------------------------
  # Attribute helpers
  # ---------------------------------------------------------------------------

  # Get raw string value of a named attribute from an xmerl attr list.
  defp get_attr(attrs, name, default) do
    atom = String.to_atom(name)

    case Enum.find(attrs, fn {:xmlAttribute, n, _, _, _, _, _, _, _, _} -> n == atom end) do
      nil -> default
      {:xmlAttribute, _, _, _, _, _, _, _, value, _} -> List.to_string(value)
    end
  end

  defp get_optional_attr(attrs, name) do
    case get_attr(attrs, name, nil) do
      nil -> nil
      val -> val
    end
  end

  defp require_string_attr(attrs, name) do
    case get_optional_attr(attrs, name) do
      nil -> {:error, "Missing required attribute: #{name}"}
      val -> {:ok, val}
    end
  end

  defp require_attr(attrs, name, parser) do
    case get_optional_attr(attrs, name) do
      nil -> {:error, "Missing required attribute: #{name}"}
      val -> parser.(val)
    end
  end

  defp get_dimension_attr(attrs, name, default) do
    case get_optional_attr(attrs, name) do
      nil ->
        default

      val ->
        case parse_dimension(val) do
          {:ok, dim} -> dim
          {:error, _} -> default
        end
    end
  end

  defp get_optional_dimension_attr(attrs, name) do
    case get_optional_attr(attrs, name) do
      nil ->
        nil

      val ->
        case parse_dimension(val) do
          {:ok, dim} -> dim
          {:error, _} -> nil
        end
    end
  end

  defp get_optional_font_size(attrs, name) do
    case get_optional_attr(attrs, name) do
      nil -> nil
      val -> parse_font_size_value(val)
    end
  end

  defp get_optional_font_weight(attrs, name) do
    case get_optional_attr(attrs, name) do
      nil -> nil
      val -> parse_font_weight_value(val)
    end
  end

  # ---------------------------------------------------------------------------
  # Padding helpers
  # ---------------------------------------------------------------------------

  # Resolves padding shorthand + per-side overrides into a {t,r,b,l} quad (pt).
  defp get_padding(attrs) do
    base = parse_spacing_value(get_attr(attrs, "padding", "0"))
    {bt, br, bb, bl} = base

    top = parse_side_spacing(attrs, "padding-top", bt)
    right = parse_side_spacing(attrs, "padding-right", br)
    bottom = parse_side_spacing(attrs, "padding-bottom", bb)
    left = parse_side_spacing(attrs, "padding-left", bl)

    {top, right, bottom, left}
  end

  defp parse_side_spacing(attrs, name, default) do
    case get_optional_attr(attrs, name) do
      nil -> default
      val -> parse_single_spacing(val)
    end
  end

  # ---------------------------------------------------------------------------
  # Border helpers
  # ---------------------------------------------------------------------------

  # Resolves the shorthand `border` attribute, then applies a per-side override.
  defp get_border_side(attrs, shorthand_name, side_name) do
    shorthand = get_optional_attr(attrs, shorthand_name)
    per_side = get_optional_attr(attrs, side_name)

    base =
      case shorthand do
        nil -> :none
        val -> parse_border_value(val)
      end

    case per_side do
      nil -> base
      val -> parse_border_value(val)
    end
  end

  # ---------------------------------------------------------------------------
  # Value parsers
  # ---------------------------------------------------------------------------

  @doc false
  @spec parse_dimension(String.t()) ::
          {:ok, {:pt, float()} | {:px, float()} | {:percent, float()} | :fill | :fit}
          | {:error, String.t()}
  def parse_dimension("fill"), do: {:ok, :fill}
  def parse_dimension("fit"), do: {:ok, :fit}

  def parse_dimension(str) do
    cond do
      String.ends_with?(str, "pt") ->
        case Float.parse(String.trim_trailing(str, "pt")) do
          {n, ""} -> {:ok, {:pt, n}}
          _ -> {:error, "Invalid pt dimension: #{str}"}
        end

      String.ends_with?(str, "px") ->
        case Float.parse(String.trim_trailing(str, "px")) do
          {n, ""} -> {:ok, {:px, n}}
          _ -> {:error, "Invalid px dimension: #{str}"}
        end

      String.ends_with?(str, "%") ->
        case Float.parse(String.trim_trailing(str, "%")) do
          {n, ""} -> {:ok, {:percent, n}}
          _ -> {:error, "Invalid % dimension: #{str}"}
        end

      true ->
        {:error, "Unknown dimension format: #{str}"}
    end
  end

  @doc false
  @spec parse_spacing(String.t()) ::
          {:ok, {number(), number(), number(), number()}} | {:error, String.t()}
  def parse_spacing(str) do
    {:ok, parse_spacing_value(str)}
  rescue
    _ -> {:error, "Invalid spacing value: #{str}"}
  end

  # Returns {top, right, bottom, left} as plain numbers (pt).
  defp parse_spacing_value(str) do
    parts = str |> String.trim() |> String.split(~r/\s+/)

    case parts do
      [all] ->
        v = parse_single_spacing(all)
        {v, v, v, v}

      [tb, lr] ->
        t = parse_single_spacing(tb)
        l = parse_single_spacing(lr)
        {t, l, t, l}

      [t, r, b, l] ->
        {parse_single_spacing(t), parse_single_spacing(r), parse_single_spacing(b),
         parse_single_spacing(l)}

      _ ->
        {0, 0, 0, 0}
    end
  end

  defp parse_single_spacing("0"), do: 0

  defp parse_single_spacing(str) do
    cond do
      String.ends_with?(str, "pt") ->
        {n, _} = Float.parse(String.trim_trailing(str, "pt"))
        n

      String.ends_with?(str, "px") ->
        {n, _} = Float.parse(String.trim_trailing(str, "px"))
        n

      true ->
        0
    end
  end

  @doc false
  @spec parse_border(String.t()) ::
          :none
          | {:border, :solid | :dashed | :dotted, number(), String.t()}
  def parse_border(str), do: parse_border_value(str)

  defp parse_border_value("none"), do: :none

  defp parse_border_value(str) do
    case String.split(String.trim(str), ~r/\s+/) do
      [style_str, width_str, color] ->
        style = parse_border_style(style_str)
        width = parse_single_spacing(width_str)
        {:border, style, width, color}

      _ ->
        :none
    end
  end

  defp parse_border_style("solid"), do: :solid
  defp parse_border_style("dashed"), do: :dashed
  defp parse_border_style("dotted"), do: :dotted
  defp parse_border_style(_), do: :solid

  defp parse_font_size_value(str) do
    case Float.parse(String.trim_trailing(str, "pt")) do
      {n, _} -> n
      :error -> 8.0
    end
  end

  defp parse_font_weight_value("bold"), do: :bold
  defp parse_font_weight_value(_), do: :normal

  defp parse_text_align_value("center"), do: :center
  defp parse_text_align_value("right"), do: :right
  defp parse_text_align_value(_), do: :left

  defp parse_vertical_align_value("center"), do: :center
  defp parse_vertical_align_value("bottom"), do: :bottom
  defp parse_vertical_align_value(_), do: :top
end
