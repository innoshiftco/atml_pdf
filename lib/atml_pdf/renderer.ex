defmodule AtmlPdf.Renderer do
  @moduledoc """
  Walks a fully-resolved ATML element tree and issues `Pdf.*` calls to produce
  a PDF document.

  ## Coordinate system

  The `pdf` library uses a **bottom-left origin**: `{0, 0}` is the lower-left
  corner of the page and `y` increases upward.  ATML layout resolves dimensions
  top-down, so the renderer must flip the Y-axis:

      pdf_y = page_height - layout_y - element_height

  ## Entry point

      {:ok, pdf_pid} = AtmlPdf.Renderer.render(resolved_doc)
      binary = Pdf.export(pdf_pid)
      Pdf.cleanup(pdf_pid)

  `render/2` accepts an optional keyword list of options (currently unused, but
  reserved for future configuration such as compression settings).
  """

  alias AtmlPdf.Element.{Col, Document, Img, Row}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Renders a fully-resolved `%Document{}` to a new `Pdf` process.

  Returns `{:ok, pid}` on success where `pid` is a live `Pdf` process.
  The caller is responsible for calling `Pdf.export/1` or `Pdf.write_to/2`
  and then `Pdf.cleanup/1`.

  Returns `{:error, reason}` if rendering fails.

  ## Examples

      iex> xml = ~s|<document width="100pt" height="100pt"></document>|
      iex> {:ok, parsed} = AtmlPdf.Parser.parse(xml)
      iex> {:ok, resolved} = AtmlPdf.Layout.resolve(parsed)
      iex> {:ok, pdf} = AtmlPdf.Renderer.render(resolved)
      iex> is_pid(pdf)
      true
      iex> Pdf.cleanup(pdf)
      :ok

  """
  @spec render(Document.t(), keyword()) :: {:ok, pid()} | {:error, String.t()}
  def render(%Document{} = doc, _opts \\ []) do
    {:ok, pdf} = Pdf.new(size: [doc.width, doc.height], compress: false)

    font_ctx = %{
      font_family: doc.font_family,
      font_size: doc.font_size,
      font_weight: doc.font_weight
    }

    {pad_top, pad_right, _pad_bottom, pad_left} = normalise_padding(doc.padding)

    inner_x = pad_left
    inner_y = pad_top
    inner_width = doc.width - pad_left - pad_right

    Pdf.set_font(pdf, font_ctx.font_family, round(font_ctx.font_size),
      bold: font_ctx.font_weight == :bold
    )

    render_rows(pdf, doc.children, inner_x, inner_y, inner_width, doc.height, font_ctx)

    {:ok, pdf}
  rescue
    e -> {:error, "Render error: #{Exception.message(e)}"}
  end

  # ---------------------------------------------------------------------------
  # Row rendering
  # ---------------------------------------------------------------------------

  defp render_rows(pdf, rows, origin_x, origin_y, _parent_width, _parent_height, font_ctx) do
    Enum.reduce(rows, origin_y, fn %Row{} = row, current_y ->
      render_row(pdf, row, origin_x, current_y, font_ctx)
      current_y + row.height
    end)
  end

  defp render_row(pdf, %Row{} = row, origin_x, origin_y, font_ctx) do
    # Draw row borders
    draw_borders(pdf, origin_x, origin_y, row.width, row.height, row)

    # Render columns side by side
    render_cols(
      pdf,
      row.children,
      origin_x + row.padding_left,
      origin_y + row.padding_top,
      row.width - row.padding_left - row.padding_right,
      row.height - row.padding_top - row.padding_bottom,
      font_ctx
    )
  end

  # ---------------------------------------------------------------------------
  # Col rendering
  # ---------------------------------------------------------------------------

  defp render_cols(pdf, cols, origin_x, origin_y, _row_inner_width, row_inner_height, font_ctx) do
    Enum.reduce(cols, origin_x, fn %Col{} = col, current_x ->
      render_col(pdf, col, current_x, origin_y, row_inner_height, font_ctx)
      current_x + col.width
    end)
  end

  defp render_col(pdf, %Col{} = col, origin_x, origin_y, _row_inner_height, font_ctx) do
    col_font_ctx = %{
      font_family: col.font_family || font_ctx.font_family,
      font_size: col.font_size || font_ctx.font_size,
      font_weight: col.font_weight || font_ctx.font_weight
    }

    # Draw col borders
    draw_borders(pdf, origin_x, origin_y, col.width, col.height, col)

    # Inner content area (after padding)
    inner_x = origin_x + col.padding_left
    inner_y = origin_y + col.padding_top
    inner_width = max(0.0, col.width - col.padding_left - col.padding_right)
    inner_height = max(0.0, col.height - col.padding_top - col.padding_bottom)

    # Collect text children to measure total text height for vertical-align
    render_col_children(
      pdf,
      col.children,
      inner_x,
      inner_y,
      inner_width,
      inner_height,
      col,
      col_font_ctx
    )
  end

  defp render_col_children(
         pdf,
         children,
         inner_x,
         inner_y,
         inner_width,
         inner_height,
         col,
         font_ctx
       ) do
    # Split children into text/img segments and nested rows.
    # For text/img we apply vertical-align within inner_height.
    # For nested rows we just stack them.
    Enum.reduce(children, inner_y, fn child, current_y ->
      case child do
        text when is_binary(text) ->
          trimmed = String.trim(text)

          if trimmed != "" do
            Pdf.set_font(pdf, font_ctx.font_family, round(font_ctx.font_size),
              bold: font_ctx.font_weight == :bold
            )

            text_height = estimate_text_height(trimmed, inner_width, font_ctx.font_size)

            y_offset =
              case col.vertical_align do
                :top -> 0.0
                :center -> max(0.0, (inner_height - text_height) / 2.0)
                :bottom -> max(0.0, inner_height - text_height)
              end

            render_text(
              pdf,
              trimmed,
              inner_x,
              current_y + y_offset,
              inner_width,
              inner_height,
              col.text_align,
              font_ctx
            )
          end

          current_y

        %Img{} = img ->
          render_img(pdf, img, inner_x, current_y, inner_width, inner_height, col.vertical_align)
          current_y + img.height

        %Row{} = nested_row ->
          render_row(pdf, nested_row, inner_x, current_y, font_ctx)
          current_y + nested_row.height
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Text rendering
  # ---------------------------------------------------------------------------

  defp render_text(pdf, text, x, layout_y, width, height, text_align, font_ctx) do
    page_height = page_height(pdf)

    # text_wrap uses top-left origin and a bounding box {width, height}.
    # Pdf lib text_wrap {x, y} = top-left of box in PDF coords (bottom-left origin).
    # layout_y is top-down from page top, so:
    #   pdf_top_of_box = page_height - layout_y
    pdf_y = page_height - layout_y

    line_height = font_ctx.font_size * 1.2

    Pdf.set_text_leading(pdf, round(line_height))

    align_opt =
      case text_align do
        :left -> :left
        :center -> :center
        :right -> :right
      end

    Pdf.text_wrap(pdf, {x, pdf_y}, {width, height}, text, align: align_opt)
  end

  # ---------------------------------------------------------------------------
  # Image rendering
  # ---------------------------------------------------------------------------

  defp render_img(pdf, %Img{} = img, x, layout_y, _inner_width, _inner_height, _vertical_align) do
    # Skip zero-dimension images (fit with no intrinsic size info)
    if img.width <= 0.0 or img.height <= 0.0 do
      :skip
    else
      page_height = page_height(pdf)
      # PDF coords: bottom-left of image box
      pdf_y = page_height - layout_y - img.height

      image_path = resolve_image_path(img.src)

      Pdf.add_image(pdf, {x, pdf_y}, image_path,
        width: img.width,
        height: img.height
      )

      if String.starts_with?(img.src, "base64:") do
        File.rm(image_path)
      end
    end
  end

  # Resolve src to a file path the pdf library can open.
  # base64-encoded images are written to a temp file.
  defp resolve_image_path("base64:" <> encoded) do
    decoded = Base.decode64!(String.trim(encoded))
    path = Path.join(System.tmp_dir!(), "atml_img_#{:erlang.unique_integer([:positive])}.png")
    File.write!(path, decoded)
    path
  end

  defp resolve_image_path(path), do: path

  # ---------------------------------------------------------------------------
  # Border rendering
  # ---------------------------------------------------------------------------

  # Draws up to 4 border lines for an element.  The `element` map must have
  # `border_top`, `border_right`, `border_bottom`, and `border_left` fields.
  defp draw_borders(pdf, x, layout_y, width, height, element) do
    page_height = page_height(pdf)

    # Layout Y is top-down; convert corners to PDF bottom-left coords.
    top = page_height - layout_y
    bottom = page_height - layout_y - height
    left = x
    right = x + width

    draw_border_line(pdf, element.border_top, {left, top}, {right, top})
    draw_border_line(pdf, element.border_right, {right, top}, {right, bottom})
    draw_border_line(pdf, element.border_bottom, {left, bottom}, {right, bottom})
    draw_border_line(pdf, element.border_left, {left, top}, {left, bottom})
  end

  defp draw_border_line(_pdf, :none, _from, _to), do: :ok

  defp draw_border_line(pdf, {:border, _style, width, color}, from, to) do
    rgb = parse_hex_color(color)
    Pdf.set_stroke_color(pdf, rgb)
    Pdf.set_line_width(pdf, width)
    Pdf.line(pdf, from, to)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Returns the current page height by querying the Pdf process.
  # Pdf.size/1 returns %{width: w, height: h}.
  defp page_height(pdf) do
    %{height: h} = Pdf.size(pdf)
    h
  end

  # Parse a hex color string like "#rrggbb" or "#rgb" to an {r, g, b} tuple
  # where each component is in 0..255.
  defp parse_hex_color("#" <> hex) when byte_size(hex) == 6 do
    <<r::binary-2, g::binary-2, b::binary-2>> = hex
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}
  end

  defp parse_hex_color("#" <> hex) when byte_size(hex) == 3 do
    <<r::binary-1, g::binary-1, b::binary-1>> = hex
    {String.to_integer(r <> r, 16), String.to_integer(g <> g, 16), String.to_integer(b <> b, 16)}
  end

  defp parse_hex_color(_), do: {0, 0, 0}

  # Normalise document padding from whatever form Layout left it in.
  defp normalise_padding({t, r, b, l}), do: {t, r, b, l}
  defp normalise_padding(n) when is_number(n), do: {n, n, n, n}
  defp normalise_padding(_), do: {0, 0, 0, 0}

  # Rough estimate of text height given content, available width, and font size.
  # Mirrors the heuristic used in AtmlPdf.Layout.
  @line_height_ratio 1.2

  defp estimate_text_height(text, width, font_size) do
    avg_char_width = font_size * 0.5
    chars_per_line = if width > 0, do: max(1, floor(width / avg_char_width)), else: 1

    line_count =
      text
      |> String.split("\n")
      |> Enum.map(fn line ->
        len = String.length(String.trim(line))
        ceil(max(len, 1) / chars_per_line)
      end)
      |> Enum.sum()

    line_count * font_size * @line_height_ratio
  end
end
