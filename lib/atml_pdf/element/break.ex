defmodule AtmlPdf.Element.Break do
  @moduledoc """
  Struct representing a `<break>` element in an ATML template.

  A `<break>` is a direct child of `<document>` that forces a page break at the
  point where it appears in the row sequence. Any rows following the `<break>`
  are rendered starting from the top of the next page.

  `<break>` has no attributes and no children.
  """

  @type t :: %__MODULE__{}

  defstruct []
end
