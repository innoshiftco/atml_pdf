defmodule AtmlPdf.Renderer do
  @moduledoc """
  Walks a fully-resolved ATML element tree and issues backend calls to produce
  a PDF document.

  ## Coordinate system

  PDF libraries typically use a **bottom-left origin**: `{0, 0}` is the lower-left
  corner of the page and `y` increases upward.  ATML layout resolves dimensions
  top-down, so the renderer must flip the Y-axis:

      pdf_y = page_height - layout_y - element_height

  ## Entry point

      {:ok, ctx} = AtmlPdf.Renderer.render(resolved_doc)
      backend = ctx.backend_module
      binary = backend.export(ctx.backend_state)
      backend.cleanup(ctx.backend_state)

  `render/2` accepts an optional keyword list of options including:
  - `:backend` - Backend module to use (defaults to application config or PdfAdapter)
  - `:compress` - Enable compression (backend-specific)
  """

  alias AtmlPdf.Element.{Col, Document, Img, Row}
  alias AtmlPdf.PdfBackend.Context

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Renders a fully-resolved `%Document{}` using the configured PDF backend.

  Returns `{:ok, ctx}` on success where `ctx` is a `%Context{}` struct containing
  the backend module and state. The caller is responsible for calling backend
  export/write and cleanup operations.

  Returns `{:error, reason}` if rendering fails.

  ## Options

  - `:backend` - Backend module implementing `AtmlPdf.PdfBackend` (optional)
  - Additional backend-specific options (e.g., `:compress`)

  ## Examples

      iex> xml = ~s|<document width="100pt" height="100pt"></document>|
      iex> {:ok, parsed} = AtmlPdf.Parser.parse(xml)
      iex> {:ok, resolved} = AtmlPdf.Layout.resolve(parsed)
      iex> {:ok, ctx} = AtmlPdf.Renderer.render(resolved)
      iex> ctx.backend_module.cleanup(ctx.backend_state)
      :ok

  """
  @spec render(Document.t(), keyword()) :: {:ok, Context.t()} | {:error, String.t()}
  def render(%Document{} = doc, opts \\ []) do
    backend = get_backend_module(opts)
    {:ok, backend_state} = backend.new(doc.width, doc.height, opts)

    ctx = %Context{
      backend_module: backend,
      backend_state: backend_state,
      page_width: doc.width,
      page_height: doc.height
    }

    font_ctx = %{
      font_family: doc.font_family,
      font_size: doc.font_size,
      font_weight: doc.font_weight
    }

    {pad_top, pad_right, _pad_bottom, pad_left} = normalise_padding(doc.padding)

    inner_x = pad_left
    inner_y = pad_top
    inner_width = doc.width - pad_left - pad_right

    # Set initial font through backend
    ctx = update_backend(ctx, fn state ->
      backend.set_font(state, font_ctx.font_family, font_ctx.font_size,
        bold: font_ctx.font_weight == :bold
      )
    end)

    ctx = render_rows(ctx, doc.children, inner_x, inner_y, inner_width, doc.height, font_ctx)

    {:ok, ctx}
  rescue
    e -> {:error, "Render error: #{Exception.message(e)}"}
  end

  # Resolves the backend module from options or application config
  defp get_backend_module(opts) do
    Keyword.get(opts, :backend) ||
      Application.get_env(:atml_pdf, :pdf_backend) ||
      AtmlPdf.PdfBackend.PdfAdapter
  end

  # Helper to update backend state and return updated context
  defp update_backend(%Context{} = ctx, fun) do
    new_state = fun.(ctx.backend_state)
    %{ctx | backend_state: new_state}
  end

  # ---------------------------------------------------------------------------
  # Row rendering
  # ---------------------------------------------------------------------------

  defp render_rows(ctx, rows, origin_x, origin_y, _parent_width, _parent_height, font_ctx) do
    {ctx, _} =
      Enum.reduce(rows, {ctx, origin_y}, fn %Row{} = row, {ctx_acc, current_y} ->
        ctx_acc = render_row(ctx_acc, row, origin_x, current_y, font_ctx)
        {ctx_acc, current_y + row.height}
      end)

    ctx
  end

  defp render_row(ctx, %Row{} = row, origin_x, origin_y, font_ctx) do
    # Draw row borders
    ctx = draw_borders(ctx, origin_x, origin_y, row.width, row.height, row)

    # Render columns side by side
    render_cols(
      ctx,
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

  defp render_cols(ctx, cols, origin_x, origin_y, _row_inner_width, row_inner_height, font_ctx) do
    {ctx, _} =
      Enum.reduce(cols, {ctx, origin_x}, fn %Col{} = col, {ctx_acc, current_x} ->
        ctx_acc = render_col(ctx_acc, col, current_x, origin_y, row_inner_height, font_ctx)
        {ctx_acc, current_x + col.width}
      end)

    ctx
  end

  defp render_col(ctx, %Col{} = col, origin_x, origin_y, _row_inner_height, font_ctx) do
    col_font_ctx = %{
      font_family: col.font_family || font_ctx.font_family,
      font_size: col.font_size || font_ctx.font_size,
      font_weight: col.font_weight || font_ctx.font_weight
    }

    # Draw col borders
    ctx = draw_borders(ctx, origin_x, origin_y, col.width, col.height, col)

    # Inner content area (after padding)
    inner_x = origin_x + col.padding_left
    inner_y = origin_y + col.padding_top
    inner_width = max(0.0, col.width - col.padding_left - col.padding_right)
    inner_height = max(0.0, col.height - col.padding_top - col.padding_bottom)

    # Collect text children to measure total text height for vertical-align
    render_col_children(
      ctx,
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
         ctx,
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
    {ctx, _} =
      Enum.reduce(children, {ctx, inner_y}, fn child, {ctx_acc, current_y} ->
        case child do
          text when is_binary(text) ->
            trimmed = String.trim(text)

            ctx_acc =
              if trimmed != "" do
                ctx_acc = update_backend(ctx_acc, fn state ->
                  ctx_acc.backend_module.set_font(state, font_ctx.font_family, font_ctx.font_size,
                    bold: font_ctx.font_weight == :bold
                  )
                end)

                text_height = estimate_text_height(trimmed, inner_width, font_ctx.font_size)

                y_offset =
                  case col.vertical_align do
                    :top -> 0.0
                    # For center alignment, center based on the font size itself, not the
                    # line height. This accounts for the visual center of the glyphs.
                    :center -> max(0.0, (inner_height - font_ctx.font_size) / 2.0)
                    :bottom -> max(0.0, inner_height - text_height)
                  end

                render_text(
                  ctx_acc,
                  trimmed,
                  inner_x,
                  current_y + y_offset,
                  inner_width,
                  inner_height,
                  col.text_align,
                  font_ctx
                )
              else
                ctx_acc
              end

            {ctx_acc, current_y}

          %Img{} = img ->
            ctx_acc = render_img(ctx_acc, img, inner_x, current_y, inner_width, inner_height, col.text_align, col.vertical_align)
            {ctx_acc, current_y + img.height}

          %Row{} = nested_row ->
            ctx_acc = render_row(ctx_acc, nested_row, inner_x, current_y, font_ctx)
            {ctx_acc, current_y + nested_row.height}
        end
      end)

    ctx
  end

  # ---------------------------------------------------------------------------
  # Text rendering
  # ---------------------------------------------------------------------------

  defp render_text(ctx, text, x, layout_y, width, height, text_align, font_ctx) do
    page_height = ctx.page_height

    # text_wrap uses top-left origin and a bounding box {width, height}.
    # PDF text_wrap {x, y} = top-left of box in PDF coords (bottom-left origin).
    # layout_y is top-down from page top, so:
    #   pdf_top_of_box = page_height - layout_y
    pdf_y = page_height - layout_y

    line_height = font_ctx.font_size * 1.2

    ctx = update_backend(ctx, fn state ->
      ctx.backend_module.set_text_leading(state, line_height)
    end)

    # CRITICAL FIX: The pdf library's text_wrap checks if line_height > box_height
    # and refuses to render if true. Since set_text_leading rounds the line_height,
    # we must ensure the box height is at least the rounded line height.
    # Otherwise text won't render and will be returned as {:continue, chunks}.
    min_box_height = round(line_height)
    adjusted_height = max(height, min_box_height)

    align_opt =
      case text_align do
        :left -> :left
        :center -> :center
        :right -> :right
      end

    update_backend(ctx, fn state ->
      ctx.backend_module.text_wrap(state, {x, pdf_y}, {width, adjusted_height}, text, align: align_opt)
    end)
  end

  # ---------------------------------------------------------------------------
  # Image rendering
  # ---------------------------------------------------------------------------

  defp render_img(ctx, %Img{} = img, x, layout_y, inner_width, inner_height, text_align, vertical_align) do
    # Skip zero-dimension images (fit with no intrinsic size info)
    if img.width <= 0.0 or img.height <= 0.0 do
      ctx
    else
      page_height = ctx.page_height

      # Horizontal alignment (same as text)
      x_offset =
        case text_align do
          :left -> 0.0
          :center -> max(0.0, (inner_width - img.width) / 2.0)
          :right -> max(0.0, inner_width - img.width)
        end

      # Vertical alignment (same as text)
      y_offset =
        case vertical_align do
          :top -> 0.0
          :center -> max(0.0, (inner_height - img.height) / 2.0)
          :bottom -> max(0.0, inner_height - img.height)
        end

      # PDF coords: bottom-left of image box
      pdf_y = page_height - (layout_y + y_offset) - img.height

      image_path = resolve_image_path(img.src)

      ctx = update_backend(ctx, fn state ->
        ctx.backend_module.add_image(state, image_path, {x + x_offset, pdf_y}, {img.width, img.height})
      end)

      if inline_image_src?(img.src) do
        File.rm(image_path)
      end

      ctx
    end
  end

  # Resolve src to a file path the pdf library can open.
  # Both the legacy "base64:<data>" prefix and the standard data URI format
  # "data:<mime>;base64,<data>" are supported.  In either case the decoded bytes
  # are written to a temp file so the `pdf` library can open them by path.

  # Standard data URI: data:image/png;base64,<data>
  # The MIME type is used to derive the temp-file extension so the pdf library
  # picks the correct decoder.
  defp resolve_image_path("data:" <> rest) do
    {mime, encoded} =
      case String.split(rest, ";base64,", parts: 2) do
        [mime, data] -> {mime, data}
        # Malformed data URI — treat remainder as raw base64, assume PNG
        _ -> {"image/png", rest}
      end

    ext = mime_to_ext(mime)
    decoded = Base.decode64!(String.trim(encoded))
    path = Path.join(System.tmp_dir!(), "atml_img_#{:erlang.unique_integer([:positive])}.#{ext}")
    File.write!(path, decoded)
    path
  end

  # Legacy "base64:<data>" prefix (kept for backward compatibility).
  defp resolve_image_path("base64:" <> encoded) do
    decoded = Base.decode64!(String.trim(encoded))
    path = Path.join(System.tmp_dir!(), "atml_img_#{:erlang.unique_integer([:positive])}.png")
    File.write!(path, decoded)
    path
  end

  defp resolve_image_path(path), do: path

  defp mime_to_ext("image/png"), do: "png"
  defp mime_to_ext("image/jpeg"), do: "jpg"
  defp mime_to_ext("image/jpg"), do: "jpg"
  defp mime_to_ext("image/gif"), do: "gif"
  defp mime_to_ext("image/webp"), do: "webp"
  defp mime_to_ext(_), do: "png"

  # Returns true for any src that was decoded to a temp file and needs cleanup.
  defp inline_image_src?("data:" <> _), do: true
  defp inline_image_src?("base64:" <> _), do: true
  defp inline_image_src?(_), do: false

  # ---------------------------------------------------------------------------
  # Border rendering
  # ---------------------------------------------------------------------------

  # Draws up to 4 border lines for an element.  The `element` map must have
  # `border_top`, `border_right`, `border_bottom`, and `border_left` fields.
  defp draw_borders(ctx, x, layout_y, width, height, element) do
    page_height = ctx.page_height

    # Layout Y is top-down; convert corners to PDF bottom-left coords.
    top = page_height - layout_y
    bottom = page_height - layout_y - height
    left = x
    right = x + width

    ctx
    |> draw_border_line(element.border_top, {left, top}, {right, top})
    |> draw_border_line(element.border_right, {right, top}, {right, bottom})
    |> draw_border_line(element.border_bottom, {left, bottom}, {right, bottom})
    |> draw_border_line(element.border_left, {left, top}, {left, bottom})
  end

  defp draw_border_line(ctx, :none, _from, _to), do: ctx

  defp draw_border_line(ctx, {:border, _style, width, color}, from, to) do
    rgb = parse_hex_color(color)

    ctx
    |> update_backend(fn state -> ctx.backend_module.set_stroke_color(state, rgb) end)
    |> update_backend(fn state -> ctx.backend_module.set_line_width(state, width) end)
    |> update_backend(fn state -> ctx.backend_module.line(state, from, to) end)
    |> update_backend(fn state -> ctx.backend_module.stroke(state) end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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
