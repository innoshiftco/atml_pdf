defmodule AtmlPdf.Element.Row do
  @moduledoc """
  Struct representing a `<row>` element in an ATML template.

  A horizontal container whose children (`<col>` elements) are laid out left to
  right. Rows stack vertically within their parent (`<document>` or `<col>`).
  """

  @typedoc "A dimension value — fixed pt/px, percentage, `fill`, or `fit`."
  @type dimension :: {:pt, number()} | {:px, number()} | {:percent, number()} | :fill | :fit

  @typedoc "A spacing quad: {top, right, bottom, left} in pt."
  @type spacing :: {number(), number(), number(), number()}

  @typedoc "A border value — either `:none` or a style/width/color triple."
  @type border ::
          :none
          | {:border, style :: :solid | :dashed | :dotted, width :: number(), color :: String.t()}

  @type t :: %__MODULE__{
          height: dimension(),
          min_height: dimension() | nil,
          max_height: dimension() | nil,
          width: dimension(),
          padding_top: number(),
          padding_right: number(),
          padding_bottom: number(),
          padding_left: number(),
          border_top: border(),
          border_right: border(),
          border_bottom: border(),
          border_left: border(),
          vertical_align: :top | :center | :bottom,
          children: list()
        }

  defstruct height: :fit,
            min_height: nil,
            max_height: nil,
            width: :fill,
            padding_top: 0,
            padding_right: 0,
            padding_bottom: 0,
            padding_left: 0,
            border_top: :none,
            border_right: :none,
            border_bottom: :none,
            border_left: :none,
            vertical_align: :top,
            children: []
end
