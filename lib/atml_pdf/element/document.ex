defmodule AtmlPdf.Element.Document do
  @moduledoc """
  Struct representing the `<document>` root element of an ATML template.

  Defines the physical dimensions of the label canvas and sets default font
  attributes that cascade to all descendants.
  """

  @typedoc "A dimension value — fixed pt/px, percentage, `fill`, or `fit`."
  @type dimension :: {:pt, number()} | {:px, number()} | {:percent, number()} | :fill | :fit

  @typedoc "A spacing quad: {top, right, bottom, left} in pt."
  @type spacing :: {number(), number(), number(), number()}

  @type t :: %__MODULE__{
          width: dimension(),
          height: dimension(),
          padding: spacing(),
          font_family: String.t(),
          font_size: number(),
          font_weight: :normal | :bold,
          children: list()
        }

  defstruct width: nil,
            height: nil,
            padding: {0, 0, 0, 0},
            font_family: "Helvetica",
            font_size: 8,
            font_weight: :normal,
            children: []
end
