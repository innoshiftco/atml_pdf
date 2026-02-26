defmodule AtmlPdf.Element.Row do
  @moduledoc """
  Struct representing a `<row>` element in an ATML template.

  A horizontal container whose children (`<col>` elements) are laid out left to
  right. Rows stack vertically within their parent (`<document>` or `<col>`).
  """

  alias AtmlPdf.Element.Types

  @type t :: %__MODULE__{
          height: Types.dimension(),
          min_height: Types.dimension() | nil,
          max_height: Types.dimension() | nil,
          width: Types.dimension(),
          padding_top: number(),
          padding_right: number(),
          padding_bottom: number(),
          padding_left: number(),
          border_top: Types.border(),
          border_right: Types.border(),
          border_bottom: Types.border(),
          border_left: Types.border(),
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
