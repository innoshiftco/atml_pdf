defmodule AtmlPdf.Element.Types do
  @moduledoc """
  Shared type definitions used across all ATML element structs.

  Centralising these types here ensures consistency and avoids duplication
  across `Document`, `Row`, `Col`, and `Img`.
  """

  @typedoc """
  A dimension value before layout resolution.

  - `{:pt, n}` — fixed size in typographic points
  - `{:px, n}` — fixed size in pixels (1 px = 0.75 pt)
  - `{:percent, n}` — relative to the parent container's dimension
  - `:fill` — grow to consume all remaining space on the parent axis
  - `:fit` — shrink-wrap to the element's own content size
  """
  @type dimension :: {:pt, number()} | {:px, number()} | {:percent, number()} | :fill | :fit

  @typedoc """
  A spacing quad `{top, right, bottom, left}` with values in typographic points.
  """
  @type spacing :: {number(), number(), number(), number()}

  @typedoc """
  A border value.

  - `:none` — no border on this side
  - `{:border, style, width, color}` — a rendered border line
  """
  @type border ::
          :none
          | {:border, style :: :solid | :dashed | :dotted, width :: number(), color :: String.t()}
end
