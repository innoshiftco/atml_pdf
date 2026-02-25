defmodule AtmlPdf.Element.Col do
  @moduledoc """
  Struct representing a `<col>` element in an ATML template.

  A vertical cell within a `<row>`. Columns are laid out horizontally within
  their parent row. May contain text, `<img>` elements, or nested `<row>`
  elements. Mixed content (text alongside child elements) is permitted.
  """

  alias AtmlPdf.Element.Types

  @type t :: %__MODULE__{
          width: Types.dimension(),
          min_width: Types.dimension() | nil,
          max_width: Types.dimension() | nil,
          height: Types.dimension(),
          padding_top: number(),
          padding_right: number(),
          padding_bottom: number(),
          padding_left: number(),
          border_top: Types.border(),
          border_right: Types.border(),
          border_bottom: Types.border(),
          border_left: Types.border(),
          font_family: String.t() | nil,
          font_size: number() | nil,
          font_weight: :normal | :bold | nil,
          text_align: :left | :center | :right,
          vertical_align: :top | :center | :bottom,
          children: list()
        }

  defstruct width: :fit,
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
