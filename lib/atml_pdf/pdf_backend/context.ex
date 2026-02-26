defmodule AtmlPdf.PdfBackend.Context do
  @moduledoc """
  Context wrapper that unifies stateful and stateless PDF backends.

  This struct provides a common interface for managing backend state,
  whether the backend is process-based (like `pdf` library) or
  immutable/functional (like `ex_guten`).

  ## Fields

  - `backend_module` - The adapter module implementing `AtmlPdf.PdfBackend`
  - `backend_state` - The internal backend state (PID, struct, etc.)
  - `page_width` - Cached page width in points
  - `page_height` - Cached page height in points
  """

  @type t :: %__MODULE__{
          backend_module: module(),
          backend_state: term(),
          page_width: float(),
          page_height: float()
        }

  defstruct [:backend_module, :backend_state, :page_width, :page_height]
end
