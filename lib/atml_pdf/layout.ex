defmodule AtmlPdf.Layout do
  @moduledoc """
  Resolves the parsed element tree into concrete point values.

  ## What this module does

  1. **Font inheritance** — propagates `font_family`, `font_size`, and
     `font_weight` top-down through `<document>` → `<row>` → `<col>`. A child
     element that declares its own value overrides the inherited one; all other
     descendants continue to inherit.

  2. **Dimension resolution** — converts every `fill`, `fit`, `%`, `pt`, and
     `px` dimension into a plain `float()` in typographic points:
     - `pt` / `px` values are converted to points (`1px = 0.75pt`).
     - `%` is resolved relative to the parent's computed dimension on the same
       axis.
      - `fit` dimensions are computed from content: character-height/width
        estimates for text nodes and intrinsic size for images. For a `<col>`
        with `width: fit`, the natural width is the widest content piece
        (longest text line × avg char width, or image width); for a `<row>`
        with `height: fit`, the natural height is the tallest column estimate.
     - `fill` siblings share the remaining space equally after all fixed and `fit`
       siblings are resolved.

  3. **Min/max constraints** — after computing the base value:
     1. Apply `min_*` as a floor.
     2. Apply `max_*` as a ceiling.

  ## Entry point

      {:ok, resolved_doc} = AtmlPdf.Layout.resolve(parsed_doc)

  The returned tree is identical in shape to the input tree but every dimension
  field holds a plain `float()` (points) instead of a tagged tuple or keyword.
  Font fields on every `Col` node are fully resolved strings/numbers.
  """

  alias AtmlPdf.Element.{Col, Document, Img, Row}

  @typedoc "Resolved dimension — a plain point value."
  @type pt :: float()

  @typedoc "Inherited font context passed down the tree."
  @type font_ctx :: %{
          font_family: String.t(),
          font_size: float(),
          font_weight: :normal | :bold
        }

  # 1 pixel = 0.75 typographic points
  @px_to_pt 0.75

  # Approximate line height for fit-content text measurement (pt).
  # We use font_size * line_height_ratio as the height for a single text line.
  @line_height_ratio 1.2

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Resolves all dimensions and propagates font inheritance in `doc`.

  Returns `{:ok, resolved_doc}` where every dimension is a plain `float()`
  (points) or `{:error, reason}` on failure.

  ## Examples

      iex> xml = ~s|<document width="100pt" height="200pt"></document>|
      iex> {:ok, parsed} = AtmlPdf.Parser.parse(xml)
      iex> {:ok, resolved} = AtmlPdf.Layout.resolve(parsed)
      iex> resolved.width
      100.0
      iex> resolved.height
      200.0

  """
  @spec resolve(Document.t()) :: {:ok, Document.t()} | {:error, String.t()}
  def resolve(%Document{} = doc) do
    font_ctx = %{
      font_family: doc.font_family,
      font_size: doc.font_size,
      font_weight: doc.font_weight
    }

    doc_width = to_pt(doc.width)
    doc_height = to_pt(doc.height)

    # Calculate inner dimensions after subtracting document padding
    {pad_top, pad_right, pad_bottom, pad_left} = normalise_padding(doc.padding)
    inner_width = doc_width - pad_left - pad_right
    inner_height = doc_height - pad_top - pad_bottom

    resolved_children = resolve_rows(doc.children, inner_width, inner_height, font_ctx)

    {:ok,
     %{
       doc
       | width: doc_width,
         height: doc_height,
         children: resolved_children
     }}
  rescue
    e -> {:error, "Layout error: #{Exception.message(e)}"}
  end

  def resolve(other) do
    {:error, "Layout error: expected a %Document{}, got: #{inspect(other)}"}
  end

  # ---------------------------------------------------------------------------
  # Row resolution
  # ---------------------------------------------------------------------------

  # Resolves a list of rows stacked vertically within a parent container of
  # `parent_width` × `parent_height`.
  defp resolve_rows(rows, parent_width, parent_height, font_ctx) do
    # First pass: resolve heights for all non-fill rows.
    # `fill` rows share what's left after the fixed/fit rows consume their space.
    # Build `acc` with prepends (O(1) each) then reverse once at the end (O(n)).
    {reversed, fill_count, used_height} =
      Enum.reduce(rows, {[], 0, 0.0}, fn row, {acc, fills, used} ->
        case row do
          %Row{height: :fill} ->
            {[{:fill_placeholder, row} | acc], fills + 1, used}

          %Row{} ->
            h = resolve_row_height(row, parent_width, parent_height, font_ctx)
            h_clamped = clamp(h, row.min_height, row.max_height, parent_height)
            {[{:resolved_height, h_clamped, row} | acc], fills, used + h_clamped}
        end
      end)

    fill_height =
      if fill_count > 0 do
        max(0.0, (parent_height - used_height) / fill_count)
      else
        0.0
      end

    reversed
    |> Enum.reverse()
    |> Enum.map(fn
      {:fill_placeholder, row} ->
        h = clamp(fill_height, row.min_height, row.max_height, parent_height)
        resolve_row_fully(row, parent_width, h, font_ctx)

      {:resolved_height, h, row} ->
        resolve_row_fully(row, parent_width, h, font_ctx)
    end)
  end

  # Computes the natural (non-fill) height of a row.
  defp resolve_row_height(%Row{height: :fit} = row, parent_width, _parent_height, font_ctx) do
    # fit: measure tallest col content; use a rough estimate based on content.
    col_height =
      row.children
      |> Enum.map(fn col ->
        col_content_height(col, parent_width, font_ctx)
      end)
      |> Enum.max(fn -> 0.0 end)

    col_height
  end

  defp resolve_row_height(%Row{height: h} = _row, parent_width, parent_height, _font_ctx) do
    resolve_dim(h, parent_width, parent_height)
  end

  # Estimates the content height of a col for fit-row calculations.
  defp col_content_height(%Col{} = col, parent_width, font_ctx) do
    resolved_font_ctx = merge_font_ctx(font_ctx, col)
    fs = resolved_font_ctx.font_size
    line_h = fs * @line_height_ratio

    padding_v = col.padding_top + col.padding_bottom

    content_h =
      col.children
      |> Enum.map(fn
        text when is_binary(text) ->
          line_count = max(1, estimate_line_count(text, parent_width, fs))
          line_count * line_h

        %Row{} = nested_row ->
          # nested rows contribute their own fit height
          resolve_row_height(nested_row, parent_width, 0.0, resolved_font_ctx)

        %Img{height: :fit} ->
          0.0

        %Img{height: h} ->
          resolve_dim(h, parent_width, 0.0)
      end)
      |> Enum.sum()

    content_h + padding_v
  end

  # Fully resolves a row: sets width/height to pt values, recurses into cols.
  defp resolve_row_fully(%Row{} = row, parent_width, resolved_height, font_ctx) do
    row_width = resolve_dim(row.width, parent_width, parent_width)
    row_width = clamp(row_width, nil, nil, parent_width)

    # Calculate inner dimensions for columns (subtract row padding)
    row_inner_width = row_width - row.padding_left - row.padding_right
    row_inner_height = resolved_height - row.padding_top - row.padding_bottom

    resolved_cols = resolve_cols(row.children, row_inner_width, row_inner_height, font_ctx)

    %{
      row
      | width: row_width,
        height: resolved_height,
        min_height: nil,
        max_height: nil,
        children: resolved_cols
    }
  end

  # ---------------------------------------------------------------------------
  # Col resolution
  # ---------------------------------------------------------------------------

  # Resolves a list of cols laid out horizontally within a row of
  # `row_width` × `row_height`.
  defp resolve_cols(cols, row_width, row_height, font_ctx) do
    # Build `acc` with prepends (O(1) each) then reverse once at the end (O(n)).
    {reversed, fill_count, used_width} =
      Enum.reduce(cols, {[], 0, 0.0}, fn col, {acc, fills, used} ->
        case col do
          %Col{width: :fill} ->
            {[{:fill_placeholder, col} | acc], fills + 1, used}

          %Col{} ->
            w = resolve_col_width(col, row_width, font_ctx)
            w_clamped = clamp(w, col.min_width, col.max_width, row_width)
            {[{:resolved_width, w_clamped, col} | acc], fills, used + w_clamped}
        end
      end)

    fill_width =
      if fill_count > 0 do
        max(0.0, (row_width - used_width) / fill_count)
      else
        0.0
      end

    reversed
    |> Enum.reverse()
    |> Enum.map(fn
      {:fill_placeholder, col} ->
        w = clamp(fill_width, col.min_width, col.max_width, row_width)
        resolve_col_fully(col, w, row_height, font_ctx)

      {:resolved_width, w, col} ->
        resolve_col_fully(col, w, row_height, font_ctx)
    end)
  end

  # Computes the natural (non-fill) width of a col.
  defp resolve_col_width(%Col{width: :fit} = col, row_width, font_ctx) do
    # fit: derive from content width, clamped to min/max, bounded by row_width.
    natural_col_width(col, font_ctx)
    |> clamp(col.min_width, col.max_width, row_width)
  end

  defp resolve_col_width(%Col{width: w}, row_width, _font_ctx) do
    resolve_dim(w, row_width, row_width)
  end

  # Estimates the natural content width of a col for :fit calculations.
  # Mirrors the heuristic used in col_content_height/3 for the width axis.
  defp natural_col_width(%Col{} = col, font_ctx) do
    resolved_font_ctx = merge_font_ctx(font_ctx, col)
    fs = resolved_font_ctx.font_size
    # Use 0.6 instead of 0.5 to account for character width variation
    # and prevent clipping on right-aligned text with wider characters
    avg_char_width = fs * 0.6

    padding_h = col.padding_left + col.padding_right

    content_w =
      col.children
      |> Enum.map(fn
        text when is_binary(text) ->
          text
          |> String.split("\n")
          |> Enum.map(fn line -> String.length(String.trim(line)) end)
          |> Enum.max(fn -> 0 end)
          |> Kernel.*(avg_char_width)

        %Row{} = nested_row ->
          # A nested row's natural width is the sum of its cols' natural widths.
          nested_row.children
          |> Enum.map(fn col -> natural_col_width(col, resolved_font_ctx) end)
          |> Enum.sum()

        %Img{width: :fit} ->
          0.0

        %Img{width: :fill} ->
          0.0

        %Img{width: img_w} ->
          resolve_dim(img_w, 0.0, 0.0)
      end)
      |> Enum.max(fn -> 0.0 end)

    content_w + padding_h
  end

  # Fully resolves a col: dimensions to pt, font inheritance, recurse into children.
  defp resolve_col_fully(%Col{} = col, resolved_width, row_height, font_ctx) do
    resolved_font_ctx = merge_font_ctx(font_ctx, col)

    col_height =
      case col.height do
        :fill -> row_height
        :fit -> col_content_height(col, resolved_width, resolved_font_ctx)
        h -> resolve_dim(h, row_height, row_height)
      end

    col_height = clamp(col_height, nil, nil, row_height)

    # Calculate inner dimensions for nested children (subtract column padding)
    col_inner_width = resolved_width - col.padding_left - col.padding_right
    col_inner_height = col_height - col.padding_top - col.padding_bottom

    resolved_children =
      resolve_col_children(
        col.children,
        col_inner_width,
        col_inner_height,
        resolved_font_ctx,
        col
      )

    %{
      col
      | width: resolved_width,
        height: col_height,
        min_width: nil,
        max_width: nil,
        font_family: resolved_font_ctx.font_family,
        font_size: resolved_font_ctx.font_size,
        font_weight: resolved_font_ctx.font_weight,
        children: resolved_children
    }
  end

  # Resolves the mixed children of a col (text strings, Img, Row).
  # col_width and col_height are the INNER dimensions (after col padding).
  defp resolve_col_children(children, col_inner_width, col_inner_height, font_ctx, _col) do
    Enum.map(children, fn
      text when is_binary(text) ->
        text

      %Row{} = row ->
        # Nested rows inside a col: resolve them with col inner dimensions as parent.
        [resolved_row] = resolve_rows([row], col_inner_width, col_inner_height, font_ctx)
        resolved_row

      %Img{} = img ->
        resolve_img(img, col_inner_width, col_inner_height)
    end)
  end

  # ---------------------------------------------------------------------------
  # Image resolution
  # ---------------------------------------------------------------------------

  defp resolve_img(%Img{} = img, parent_width, parent_height) do
    w = resolve_img_dim(img.width, parent_width)
    h = resolve_img_dim(img.height, parent_height)

    w = apply_img_constraints(w, img.min_width, img.max_width, parent_width)
    h = apply_img_constraints(h, img.min_height, img.max_height, parent_height)

    # Proportional scaling when exactly one axis is fit
    {w, h} =
      case {img.width, img.height} do
        {:fit, other} when other != :fit ->
          # height is fixed; can't determine aspect ratio without image data → use 0
          {0.0, h}

        {other, :fit} when other != :fit ->
          # width is fixed; similarly
          {w, 0.0}

        _ ->
          {w, h}
      end

    %{img | width: w, height: h, min_width: nil, max_width: nil, min_height: nil, max_height: nil}
  end

  defp resolve_img_dim(:fit, _parent), do: 0.0
  defp resolve_img_dim(:fill, parent), do: parent * 1.0
  defp resolve_img_dim(dim, parent), do: resolve_dim(dim, parent, parent)

  defp apply_img_constraints(val, min_d, max_d, parent) do
    clamp(val, min_d, max_d, parent)
  end

  # ---------------------------------------------------------------------------
  # Font inheritance
  # ---------------------------------------------------------------------------

  # Merges the inherited font context with any overrides declared on a Col.
  # Rows do not carry font fields, so they pass the context through unchanged.
  defp merge_font_ctx(ctx, %Col{} = col) do
    %{
      font_family: col.font_family || ctx.font_family,
      font_size: col.font_size || ctx.font_size,
      font_weight: col.font_weight || ctx.font_weight
    }
  end

  # ---------------------------------------------------------------------------
  # Dimension utilities
  # ---------------------------------------------------------------------------

  # Normalise padding to a {top, right, bottom, left} tuple.
  defp normalise_padding({t, r, b, l}), do: {t, r, b, l}
  defp normalise_padding(n) when is_number(n), do: {n, n, n, n}
  defp normalise_padding(_), do: {0, 0, 0, 0}

  # Converts a tagged dimension to a plain pt float.
  # `parent_same_axis` is used for % resolution.
  # `parent_cross_axis` is the fallback for fill when called in single-axis context.
  defp resolve_dim({:pt, n}, _parent, _cross), do: n * 1.0
  defp resolve_dim({:px, n}, _parent, _cross), do: n * @px_to_pt
  defp resolve_dim({:percent, n}, parent, _cross), do: parent * n / 100.0
  defp resolve_dim(:fill, parent, _cross), do: parent * 1.0
  defp resolve_dim(:fit, _parent, _cross), do: 0.0

  # Converts a bare pt/px/tagged dimension at the document level (no parent).
  defp to_pt({:pt, n}), do: n * 1.0
  defp to_pt({:px, n}), do: n * @px_to_pt
  defp to_pt({:percent, _}), do: 0.0
  defp to_pt(:fill), do: 0.0
  defp to_pt(:fit), do: 0.0
  defp to_pt(n) when is_number(n), do: n * 1.0

  # Applies min/max constraints. `nil` means no constraint.
  # Constraint dimensions are resolved relative to `parent`.
  defp clamp(value, min_d, max_d, parent) do
    value
    |> apply_min(min_d, parent)
    |> apply_max(max_d, parent)
  end

  defp apply_min(value, nil, _parent), do: value

  defp apply_min(value, min_d, parent) do
    min_pt = resolve_dim(min_d, parent, parent)
    max(value, min_pt)
  end

  defp apply_max(value, nil, _parent), do: value

  defp apply_max(value, max_d, parent) do
    max_pt = resolve_dim(max_d, parent, parent)
    min(value, max_pt)
  end

  # ---------------------------------------------------------------------------
  # Content measurement helpers
  # ---------------------------------------------------------------------------

  # Very rough estimate of how many lines `text` occupies in a col of `width` pt
  # using `font_size` pt. This is a heuristic — a real implementation would use
  # actual glyph metrics from the font.
  defp estimate_line_count(text, width, font_size) do
    # Average character width ≈ 0.5 × font_size for proportional fonts.
    avg_char_width = font_size * 0.5
    chars_per_line = if width > 0, do: floor(width / avg_char_width), else: 1
    chars_per_line = max(chars_per_line, 1)

    text
    |> String.split("\n")
    |> Enum.map(fn line ->
      len = String.length(String.trim(line))
      ceil(max(len, 1) / chars_per_line)
    end)
    |> Enum.sum()
  end
end
