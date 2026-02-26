defmodule AtmlPdf.PdfBackend do
  @moduledoc """
  Behaviour defining the contract for PDF generation backends.

  This behaviour allows atml_pdf to support multiple PDF libraries (e.g., `pdf`, `ex_guten`)
  by defining a common interface for PDF operations.

  ## Implementing a Backend

  To create a new backend, implement all callbacks in this behaviour:

      defmodule MyCustomAdapter do
        @behaviour AtmlPdf.PdfBackend

        @impl true
        def new(width, height, opts), do: ...
        # ... implement all other callbacks
      end

  ## Configuration

  Set the default backend in your application config:

      config :atml_pdf,
        pdf_backend: AtmlPdf.PdfBackend.ExGutenAdapter

  Or override per-document:

      AtmlPdf.render(xml, path, backend: AtmlPdf.PdfBackend.PdfAdapter)
  """

  @doc """
  Creates a new PDF document with the specified dimensions.

  ## Parameters
  - `width` - Page width in points
  - `height` - Page height in points
  - `opts` - Backend-specific options

  ## Returns
  `{:ok, backend_state}` where `backend_state` is the internal state
  representation (e.g., a PID for process-based backends, a struct for
  functional backends).
  """
  @callback new(width :: float(), height :: float(), opts :: keyword()) ::
              {:ok, backend_state :: term()}

  @doc """
  Sets the current font for text rendering.

  ## Parameters
  - `state` - The backend state
  - `family` - Font family name (e.g., "Helvetica", "Times-Roman")
  - `size` - Font size in points
  - `opts` - Font options (e.g., `bold: true`)

  ## Returns
  Updated backend state
  """
  @callback set_font(
              state :: term(),
              family :: String.t(),
              size :: float(),
              opts :: keyword()
            ) :: term()

  @doc """
  Renders text within a bounding box with optional text wrapping.

  ## Parameters
  - `state` - The backend state
  - `position` - `{x, y}` tuple for bottom-left corner
  - `dimensions` - `{width, height}` tuple for bounding box
  - `text` - The text content to render
  - `opts` - Text options (e.g., `align: :left`)

  ## Returns
  Updated backend state
  """
  @callback text_wrap(
              state :: term(),
              position :: {float(), float()},
              dimensions :: {float(), float()},
              text :: String.t(),
              opts :: keyword()
            ) :: term()

  @doc """
  Sets the line height (leading) for text rendering.

  ## Parameters
  - `state` - The backend state
  - `leading` - Line height in points

  ## Returns
  Updated backend state
  """
  @callback set_text_leading(state :: term(), leading :: float()) :: term()

  @doc """
  Embeds an image in the PDF at the specified position and size.

  ## Parameters
  - `state` - The backend state
  - `image_data` - Image binary data or path
  - `position` - `{x, y}` tuple for bottom-left corner
  - `dimensions` - `{width, height}` tuple for image size

  ## Returns
  Updated backend state
  """
  @callback add_image(
              state :: term(),
              image_data :: binary() | String.t(),
              position :: {float(), float()},
              dimensions :: {float(), float()}
            ) :: term()

  @doc """
  Sets the stroke color for drawing operations.

  ## Parameters
  - `state` - The backend state
  - `color` - Color specification (e.g., `:black`, `{r, g, b}`)

  ## Returns
  Updated backend state
  """
  @callback set_stroke_color(state :: term(), color :: atom() | tuple()) :: term()

  @doc """
  Sets the line width for drawing operations.

  ## Parameters
  - `state` - The backend state
  - `width` - Line width in points

  ## Returns
  Updated backend state
  """
  @callback set_line_width(state :: term(), width :: float()) :: term()

  @doc """
  Draws a line segment from one point to another.

  ## Parameters
  - `state` - The backend state
  - `from` - `{x, y}` tuple for start point
  - `to` - `{x, y}` tuple for end point

  ## Returns
  Updated backend state
  """
  @callback line(state :: term(), from :: {float(), float()}, to :: {float(), float()}) :: term()

  @doc """
  Strokes the current path (renders lines/borders).

  ## Parameters
  - `state` - The backend state

  ## Returns
  Updated backend state
  """
  @callback stroke(state :: term()) :: term()

  @doc """
  Queries the page dimensions.

  ## Parameters
  - `state` - The backend state

  ## Returns
  `{width, height}` tuple in points
  """
  @callback size(state :: term()) :: {float(), float()}

  @doc """
  Exports the PDF document as a binary.

  ## Parameters
  - `state` - The backend state

  ## Returns
  Binary representation of the PDF
  """
  @callback export(state :: term()) :: binary()

  @doc """
  Writes the PDF document to a file.

  ## Parameters
  - `state` - The backend state
  - `path` - File path to write to

  ## Returns
  `:ok` on success, `{:error, reason}` on failure
  """
  @callback write_to(state :: term(), path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Cleans up backend resources (e.g., closes processes, releases memory).

  ## Parameters
  - `state` - The backend state

  ## Returns
  `:ok`
  """
  @callback cleanup(state :: term()) :: :ok
end
