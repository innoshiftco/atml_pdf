defmodule AtmlPdf.Element.Img do
  @moduledoc """
  Struct representing an `<img>` element in an ATML template.

  An inline image element. Must be a direct child of `<col>`.

  The `src` field accepts either a local file path or a base64-encoded string
  prefixed with `"base64:"`.

  ## Scaling behaviour

  - If only one axis is fixed and the other is `fit`, the image scales
    proportionally, preserving aspect ratio.
  - If both axes are fixed, the image is stretched to fill without preserving
    aspect ratio.
  - If both are `fit`, the image renders at its intrinsic size.
  """

  alias AtmlPdf.Element.Types

  @type t :: %__MODULE__{
          src: String.t(),
          width: Types.dimension(),
          height: Types.dimension(),
          min_width: Types.dimension() | nil,
          max_width: Types.dimension() | nil,
          min_height: Types.dimension() | nil,
          max_height: Types.dimension() | nil
        }

  defstruct src: nil,
            width: :fit,
            height: :fit,
            min_width: nil,
            max_width: nil,
            min_height: nil,
            max_height: nil
end
