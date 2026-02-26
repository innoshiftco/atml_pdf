defmodule AtmlPdf.PdfBackend.ExGutenAdapter do
  @moduledoc """
  Adapter for the `ex_guten` hex package.

  This adapter wraps the ExGuten library to conform to the
  `AtmlPdf.PdfBackend` behaviour. ExGuten uses an immutable struct-based
  API where operations return updated PDF state.

  ## Features

  - Full UTF-8 support with TrueType/OpenType fonts
  - Immutable struct-based API (functional approach)
  - Built-in PDF standard fonts + custom font embedding
  - PNG and JPEG image embedding with alpha channel support
  - Advanced text rendering with paragraph layout

  ## Advantages over PdfAdapter

  - ✅ Full Unicode support (CJK, emoji, symbols)
  - ✅ TrueType/OpenType font embedding
  - ✅ Font subsetting for smaller PDFs
  - ✅ Immutable, testable API

  ## Usage

  ```elixir
  # Configure as default backend
  config :atml_pdf, pdf_backend: AtmlPdf.PdfBackend.ExGutenAdapter

  # Or use per-document
  AtmlPdf.render(xml, path, backend: AtmlPdf.PdfBackend.ExGutenAdapter)
  ```

  ## Font registration

  ### Bundled fonts (automatic)

  Every `.ttf` file in `priv/fonts/` is registered automatically at startup
  using its filename stem as the font name:

  - `NotoSans-Regular.ttf`  → registered as both `"NotoSans-Regular"` and
    `"NotoSans"` (canonical alias)
  - `NotoSansThai-Regular.ttf` → registered as `"NotoSansThai-Regular"`

  Drop any additional TTF into `priv/fonts/` and it becomes available in ATML
  `font-family` attributes immediately — no code changes required.

  ### Extra fonts via application config

  Fonts outside `priv/fonts/` can be registered via application config. Each
  entry is a `{font_name, path}` tuple where `font_name` is the exact string
  used in ATML `font-family` attributes.

  ```elixir
  config :atml_pdf, :fonts, [
    {"NotoSansCJK-Regular", "/usr/share/fonts/NotoSansCJK-Regular.ttf"}
  ]
  ```

  Missing files are skipped with a warning; valid entries are registered in
  addition to any bundled fonts.

  ### Font resolution

  When rendering text the ATML `font-family` value is resolved to a registered
  font name using this priority:

  1. Exact match against registered (embedded) fonts.
  2. Case-insensitive match against registered fonts.
  3. Hard-coded aliases for PDF built-in fonts (Helvetica, Times, Courier).
  4. Fall back to `"NotoSans"`.

  All registered TTF fonts are automatically included in the fallback chain
  so glyphs not covered by the primary font are rendered by the first fallback
  that supports them.
  """

  @behaviour AtmlPdf.PdfBackend

  @noto_sans_font_name "NotoSans"
  @priv_fonts_dir Path.join(:code.priv_dir(:atml_pdf), "fonts")

  @impl true
  def new(width, height, _opts) do
    pdf =
      ExGuten.new()
      |> ExGuten.page_size({width, height})
      |> register_priv_fonts()
      |> register_config_fonts()

    {:ok, pdf}
  end

  # Auto-register every TTF file in priv/fonts/ using the filename stem as the
  # font name. For example:
  #   NotoSans-Regular.ttf  → "NotoSans-Regular"
  #   NotoSansThai-Regular.ttf → "NotoSansThai-Regular"
  #
  # NotoSans-Regular.ttf is also registered under the canonical short alias
  # "NotoSans" so that `font-family="NotoSans"` in ATML works as expected.
  defp register_priv_fonts(pdf) do
    fonts_dir = @priv_fonts_dir

    if File.dir?(fonts_dir) do
      fonts_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".ttf"))
      |> Enum.reduce(pdf, fn filename, acc ->
        path = Path.join(fonts_dir, filename)
        stem = Path.rootname(filename)
        acc = ExGuten.register_ttf_font(acc, stem, path)

        # Register NotoSans-Regular under the short alias "NotoSans" too.
        if stem == "NotoSans-Regular" do
          ExGuten.register_ttf_font(acc, @noto_sans_font_name, path)
        else
          acc
        end
      end)
    else
      pdf
    end
  end

  # Register fonts declared in `config :atml_pdf, :fonts, [{"Name", "/path/to/font.ttf"}]`.
  defp register_config_fonts(pdf) do
    :atml_pdf
    |> Application.get_env(:fonts, [])
    |> Enum.reduce(pdf, fn
      {name, path}, acc when is_binary(name) and is_binary(path) ->
        if File.exists?(path) do
          ExGuten.register_ttf_font(acc, name, path)
        else
          IO.warn("atml_pdf font not found, skipping: #{name} at #{path}")
          acc
        end

      other, acc ->
        IO.warn("atml_pdf invalid font config entry, skipping: #{inspect(other)}")
        acc
    end)
  end

  @impl true
  def set_font(pdf, family, size, opts) do
    font_name = resolve_font(pdf, family, opts)
    ExGuten.set_font(pdf, font_name, size)
  end

  @impl true
  def text_wrap(pdf, {x, y}, {width, _height}, text, opts) do
    # IMPORTANT: Both pdf library and ExGuten use bottom-left origin for PDF coordinates.
    # The {x, y} parameter represents the TOP-LEFT corner of the text bounding box.
    # {width, height} is the size of the box.
    #
    # For ExGuten's text_at(x, y, text):
    # - x, y is the BASELINE position (bottom-left of the first line)
    # - We need to calculate the baseline from the top of the box

    align = Keyword.get(opts, :align, :left)

    # Get current font size from PDF state
    # ExGuten stores current_font as {font_name, size}
    font_size =
      case pdf.current_font do
        {_name, size} -> size
        # Default fallback
        _ -> 12.0
      end

    # Calculate baseline offset and line height
    baseline_offset = font_size * 0.8
    line_height = font_size * 1.2

    # Wrap text into lines that fit within the width
    lines = wrap_text(text, width, font_size)

    # All embedded (TTF) fonts act as fallbacks for glyph coverage.
    # This ensures config-registered fonts (e.g. NotoSansThai, NotoSansCJK)
    # are tried automatically for any glyph the primary font can't render.
    fallback_fonts =
      pdf.embedded_fonts
      |> Map.keys()
      |> Enum.reject(&(&1 == primary_font_name(pdf)))

    # Render each line
    lines
    |> Enum.with_index()
    |> Enum.reduce(pdf, fn {line, index}, pdf_acc ->
      # Calculate y position for this line (moving down for each line)
      line_y = y - baseline_offset - index * line_height

      # Calculate x position based on alignment
      estimated_char_width = font_size * 0.5
      estimated_text_width = String.length(line) * estimated_char_width

      text_x =
        case align do
          :left ->
            x

          :center ->
            box_center = x + width / 2
            box_center - estimated_text_width / 2

          :right ->
            x + width - estimated_text_width

          _ ->
            x
        end

      # Render this line, using NotoSans fallback for Asian glyphs
      ExGuten.text_at_with_fallback(pdf_acc, text_x, line_y, line, fallback_fonts)
    end)
  end

  @impl true
  def set_text_leading(pdf, _leading) do
    # ExGuten handles line spacing differently
    # Line spacing is set per text_paragraph call
    # We'll store this in PDF metadata if needed later
    pdf
  end

  @impl true
  def add_image(pdf, image_data, {x, y}, {width, height}) do
    # Determine image type and add accordingly
    cond do
      # Check if it's a file path
      is_binary(image_data) and File.exists?(image_data) ->
        add_image_from_file(pdf, image_data, {x, y}, {width, height})

      # Check if it's binary image data (PNG or JPEG)
      is_binary(image_data) ->
        add_image_from_binary(pdf, image_data, {x, y}, {width, height})

      true ->
        pdf
    end
  end

  @impl true
  def set_stroke_color(pdf, color) do
    # Convert color to RGB tuple
    rgb = normalize_color(color)
    ExGuten.set_stroke_color(pdf, rgb)
  end

  @impl true
  def set_line_width(pdf, width) do
    ExGuten.set_line_width(pdf, width)
  end

  @impl true
  def line(pdf, {x1, y1}, {x2, y2}) do
    pdf
    |> ExGuten.line(x1, y1, x2, y2)
  end

  @impl true
  def stroke(pdf) do
    ExGuten.stroke(pdf)
  end

  @impl true
  def size(pdf) do
    # Extract page dimensions from PDF state
    # ExGuten stores page size in the state
    # Convert to floats to match PdfAdapter behavior
    case pdf.page_size do
      {width, height} -> {width * 1.0, height * 1.0}
      # Default A4 size
      _ -> {595.0, 842.0}
    end
  end

  @impl true
  def export(pdf) do
    ExGuten.export(pdf)
  end

  @impl true
  def write_to(pdf, path) do
    case ExGuten.save(pdf, path) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def cleanup(_pdf) do
    # ExGuten uses immutable structs, no cleanup needed
    :ok
  end

  # Private helper functions

  defp wrap_text(text, max_width, font_size) do
    # Estimate character width (average for proportional fonts)
    char_width = font_size * 0.5

    # Calculate approximate max characters per line
    max_chars = trunc(max_width / char_width)

    # If text fits in one line, return as-is
    if String.length(text) <= max_chars do
      [text]
    else
      # Word-wrap algorithm
      words = String.split(text, " ")
      wrap_words(words, max_chars, [], [])
    end
  end

  defp wrap_words([], _max_chars, current_line, lines) do
    # Finish last line
    if current_line == [] do
      Enum.reverse(lines)
    else
      Enum.reverse([Enum.join(Enum.reverse(current_line), " ") | lines])
    end
  end

  defp wrap_words([word | rest], max_chars, current_line, lines) do
    # Calculate current line length
    current_length =
      if current_line == [] do
        0
      else
        current_line
        |> Enum.reverse()
        |> Enum.join(" ")
        |> String.length()
      end

    # Calculate length if we add this word
    word_length = String.length(word)
    space_length = if current_line == [], do: 0, else: 1
    new_length = current_length + space_length + word_length

    cond do
      # Word fits on current line
      new_length <= max_chars ->
        wrap_words(rest, max_chars, [word | current_line], lines)

      # Word doesn't fit, start new line
      current_line != [] ->
        line = Enum.join(Enum.reverse(current_line), " ")
        wrap_words([word | rest], max_chars, [], [line | lines])

      # Word is too long for any line, split it
      word_length > max_chars ->
        {first_part, rest_part} = String.split_at(word, max_chars)
        wrap_words([rest_part | rest], max_chars, [], [first_part | lines])

      # Start new line with this word
      true ->
        wrap_words(rest, max_chars, [word], lines)
    end
  end

  # Resolve an ATML font-family name to a font name that ExGuten knows about.
  #
  # Strategy (in order):
  #   1. Exact match in embedded_fonts (TTF fonts registered at init).
  #   2. Case-insensitive match in embedded_fonts.
  #   3. Hard-coded aliases for PDF built-in fonts (Helvetica, Times, Courier).
  #   4. Fall back to @noto_sans_font_name, which is always registered from priv/fonts/.
  defp resolve_font(pdf, family, opts) do
    bold = Keyword.get(opts, :bold, false)
    registered = Map.keys(pdf.embedded_fonts)

    # 1. Exact match
    cond do
      family in registered ->
        family

      # 2. Case-insensitive match
      (match = Enum.find(registered, &(String.downcase(&1) == String.downcase(family)))) != nil ->
        match

      # 3. PDF built-in font aliases (not in embedded_fonts)
      true ->
        case {String.downcase(family), bold} do
          {"helvetica", false} -> "Helvetica"
          {"helvetica", true} -> "Helvetica-Bold"
          {"times", false} -> "Times-Roman"
          {"times", true} -> "Times-Bold"
          {"times-roman", false} -> "Times-Roman"
          {"times-roman", true} -> "Times-Bold"
          {"courier", false} -> "Courier"
          {"courier", true} -> "Courier-Bold"
          # 4. Default
          _ -> @noto_sans_font_name
        end
    end
  end

  defp normalize_color(:black), do: {0.0, 0.0, 0.0}
  defp normalize_color(:white), do: {1.0, 1.0, 1.0}

  defp normalize_color({r, g, b}) when r > 1 or g > 1 or b > 1 do
    # Convert 0-255 range to 0.0-1.0 range
    {r / 255.0, g / 255.0, b / 255.0}
  end

  defp normalize_color({r, g, b}), do: {r, g, b}

  defp normalize_color(color) when is_atom(color) do
    # Default to black for unknown colors
    {0.0, 0.0, 0.0}
  end

  defp add_image_from_file(pdf, path, {x, y}, {width, height}) do
    ext = Path.extname(path) |> String.downcase()

    case ext do
      ".jpg" -> ExGuten.image_jpeg(pdf, x, y, width, height, path)
      ".jpeg" -> ExGuten.image_jpeg(pdf, x, y, width, height, path)
      ".png" -> ExGuten.image_png(pdf, x, y, width, height, path)
      _ -> pdf
    end
  end

  defp add_image_from_binary(pdf, binary, {x, y}, {width, height}) do
    # Detect image type from binary header
    case binary do
      <<0xFF, 0xD8, 0xFF, _rest::binary>> ->
        # JPEG magic bytes
        write_temp_and_add(pdf, binary, :jpeg, {x, y}, {width, height})

      <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> ->
        # PNG magic bytes
        write_temp_and_add(pdf, binary, :png, {x, y}, {width, height})

      _ ->
        pdf
    end
  end

  defp write_temp_and_add(pdf, binary, type, {x, y}, {width, height}) do
    # Write binary to temporary file for ExGuten to read
    ext = if type == :jpeg, do: ".jpg", else: ".png"

    temp_path =
      Path.join(System.tmp_dir!(), "atml_pdf_#{:erlang.unique_integer([:positive])}#{ext}")

    case File.write(temp_path, binary) do
      :ok ->
        result =
          case type do
            :jpeg -> ExGuten.image_jpeg(pdf, x, y, width, height, temp_path)
            :png -> ExGuten.image_png(pdf, x, y, width, height, temp_path)
          end

        # Clean up temp file
        File.rm(temp_path)
        result

      {:error, _} ->
        pdf
    end
  end

  defp primary_font_name(pdf) do
    case pdf.current_font do
      {name, _size} -> name
      _ -> nil
    end
  end
end
