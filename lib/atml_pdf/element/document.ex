defmodule AtmlPdf.Element.Document do
  @moduledoc """
  Struct representing the `<document>` root element of an ATML template.

  Defines the physical dimensions of the label canvas and sets default font
  attributes that cascade to all descendants.
  """

  alias AtmlPdf.Element.Types

  @type t :: %__MODULE__{
          width: Types.dimension(),
          height: Types.dimension(),
          padding: Types.spacing(),
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
