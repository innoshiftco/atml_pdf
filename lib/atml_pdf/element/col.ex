defmodule AtmlPdf.Element.Col do
  @moduledoc """
  Struct representing a `<col>` element in an ATML template.

  A vertical cell within a `<row>`. Columns are laid out horizontally within
  their parent row. May contain text, `<img>` elements, or nested `<row>`
  elements. Mixed content (text alongside child elements) is permitted.
  """

  @typedoc "A dimension value — fixed pt/px, percentage, `fill`, or `fit`."
  @type dimension :: {:pt, number()} | {:px, number()} | {:percent, number()} | :fill | :fit

  @typedoc "A border value — either `:none` or a style/width/color triple."
  @type border ::
          :none
          | {:border, style :: :solid | :dashed | :dotted, width :: number(), color :: String.t()}

  @type t :: %__MODULE__{
          width: dimension(),
          min_width: dimension() | nil,
          max_width: dimension() | nil,
          height: dimension(),
          padding_top: number(),
          padding_right: number(),
          padding_bottom: number(),
          padding_left: number(),
          border_top: border(),
          border_right: border(),
          border_bottom: border(),
          border_left: border(),
          font_family: String.t() | nil,
          font_size: number() | nil,
          font_weight: :normal | :bold | nil,
          text_align: :left | :center | :right,
          vertical_align: :top | :center | :bottom,
          children: list()
        }

  defstruct width: :fill,
            min_width: nil,
            max_width: nil,
            height: :fill,
            padding_top: 0,
            padding_right: 0,
            padding_bottom: 0,
            padding_left: 0,
            border_top: :none,
            border_right: :none,
            border_bottom: :none,
            border_left: :none,
            font_family: nil,
            font_size: nil,
            font_weight: nil,
            text_align: :left,
            vertical_align: :top,
            children: []
end
