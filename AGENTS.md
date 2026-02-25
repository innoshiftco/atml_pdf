# AGENTS.md — atml_pdf

Guidance for agentic coding agents working in this repository.

## Project Overview

`atml_pdf` is an Elixir library that parses **ATML (AWB Template Markup Language)** — an XML-based format for defining Airway Bill (shipping label) layouts — and renders the result to PDF. The project is early-stage; the domain specification lives in `ATML_language_specs.md`.

**Language:** Elixir (≥ 1.18), running on the BEAM/OTP  
**Build tool:** Mix (Elixir's built-in build and package manager)  
**Testing framework:** ExUnit (built-in, no third-party test library)

---

## Build, Lint, Test, Format Commands

```bash
# Install dependencies
mix deps.get

# Compile
mix compile

# Run all tests
mix test

# Run tests with coverage report
mix test --cover

# Run a single test file
mix test test/atml_pdf_test.exs

# Run a single test by file:line (preferred way to target one test)
mix test test/atml_pdf_test.exs:5

# Run only tests matching a tag
mix test --only tag_name

# Re-run only previously failing tests
mix test --failed

# Run only tests touched by code changes since last run
mix test --stale

# Format all source files
mix format

# Check formatting without modifying files (use in CI / pre-commit)
mix format --check-formatted

# Remove build artifacts
mix clean
```

> There is no Makefile. All tasks go through `mix`.

---

## Linter / Static Analysis

No linter or type-checker dependency (Credo, Dialyxir, Sobelow) has been added yet. When they are added:

```bash
mix credo --strict          # Credo lint
mix dialyzer                # Dialyxir type analysis
mix sobelow                 # Security audit (Phoenix/web only)
```

Until then, `mix format --check-formatted` is the only automated style check.

---

## Formatter Configuration

`.formatter.exs` is present and applies `mix format` to:

```
{mix,.formatter}.exs
{config,lib,test}/**/*.{ex,exs}
```

Always run `mix format` before committing. Do not disable formatter settings without a compelling reason.

---

## Code Style Guidelines

### Naming Conventions

| Construct | Convention | Example |
|-----------|-----------|---------|
| Modules | `PascalCase` | `AtmlPdf.Parser` |
| Functions / variables | `snake_case` | `parse_element/1` |
| Atoms / constants | `snake_case` | `:ok`, `:error`, `:label` |
| Module attributes | `snake_case` prefixed with `@` | `@default_font_size` |
| Test modules | Mirror tested module + `Test` | `AtmlPdf.ParserTest` |
| Test files | Mirror source path under `test/`, suffix `_test.exs` | `test/atml_pdf/parser_test.exs` |

### Module Structure

Follow this ordering inside every module:

1. `@moduledoc` (required — never `@moduledoc false` in public API modules)
2. `use`, `import`, `alias`, `require` directives (in that order, alphabetically within each group)
3. `@type` and `@typedoc` declarations
4. Module attributes (`@foo`)
5. Public functions (`def`) with `@doc` above each
6. Private functions (`defp`) — no `@doc`

```elixir
defmodule AtmlPdf.Parser do
  @moduledoc """
  Parses ATML XML into an element tree.
  """

  alias AtmlPdf.Element.{Col, Img, Label, Row}

  @type parse_result :: {:ok, Label.t()} | {:error, String.t()}

  @doc """
  Parses an ATML XML string.

  ## Examples

      iex> AtmlPdf.Parser.parse("<label .../>")
      {:ok, %AtmlPdf.Element.Label{}}

  """
  @spec parse(String.t()) :: parse_result()
  def parse(xml) do
    # ...
  end

  defp validate_root(element) do
    # ...
  end
end
```

### Imports and Aliases

- Prefer `alias` over `import` to keep the call site readable.
- Use `alias AtmlPdf.Element.{Label, Row, Col}` multi-alias syntax for related modules.
- Never `import` a module globally when only a few functions are needed — use explicit calls or a targeted `import SomeModule, only: [some_fn: 1]`.
- `use ExUnit.Case` in test files; add `async: true` when tests have no shared state or side effects.

### Types and Specs

- Add `@spec` to every public function.
- Define `@type t :: %__MODULE__{...}` for structs.
- Use `@typedoc` to document non-obvious types.
- Prefer specific types (`String.t()`, `non_neg_integer()`) over `any()`.

### Error Handling

Use the standard Elixir `{:ok, value}` / `{:error, reason}` tuple convention:

```elixir
# Good
def parse(xml) do
  case do_parse(xml) do
    {:ok, result}    -> {:ok, result}
    {:error, reason} -> {:error, "Parse failed: #{reason}"}
  end
end

# Avoid raising for expected failure paths
def parse!(xml) do
  case parse(xml) do
    {:ok, result}    -> result
    {:error, reason} -> raise ArgumentError, reason
  end
end
```

- Provide a `!`-suffixed raising variant only when callers genuinely want to crash on failure.
- Use `with` for chaining multiple `{:ok, _}` steps without nested `case` blocks.
- Pattern match on `{:ok, _}` / `{:error, _}` at the call site — do not swallow errors.

### Pattern Matching and Guards

- Prefer pattern matching in function heads over `if`/`cond` inside the body.
- Use guards (`when`) for type checks and simple predicates.
- Avoid deeply nested `case` or `cond` — refactor into private helpers or `with`.

### Doctests

- Every public function that has a `@doc` **must** include at least one `## Examples` block with `iex>` expressions.
- The corresponding test module must call `doctest MyModule` so those examples are executed automatically.

### Async Patterns

- Use `Task.async/Task.await` for fire-and-forget parallelism.
- Use `Task.async_stream` for parallel processing of collections.
- Prefer `GenServer` only when mutable state or process lifecycle management is required.

---

## Testing Conventions

- Test files live under `test/`, mirror the `lib/` directory structure, and end in `_test.exs`.
- Bootstrap file is `test/test_helper.exs` (contains only `ExUnit.start()`; do not add global setup there).
- Use `describe "function_name/arity"` blocks to group tests for the same function.
- Use `setup` / `setup_all` callbacks for shared fixtures; prefer `setup` (per-test) over `setup_all`.
- Mark slow or integration tests with `@tag :integration` and exclude them from the default run:
  ```bash
  mix test --exclude integration
  mix test --only integration
  ```
- Use `assert`, `refute`, `assert_raise`, `assert_receive` — avoid raw boolean checks.
- Keep test descriptions concise and in plain English (`test "returns error when XML is malformed"`).

---

## Architecture

The intended pipeline is:

```
ATML XML string
  → AtmlPdf.Parser        (XML → element tree)
  → AtmlPdf.Layout        (resolve dimensions, spacing, inheritance)
  → AtmlPdf.Renderer      (element tree → PDF bytes)
```

Anticipated module structure:

```
lib/
  atml_pdf.ex               # Public API
  atml_pdf/
    parser.ex               # XML parsing
    layout.ex               # Layout resolution
    renderer.ex             # PDF rendering
    element/
      label.ex              # <label> root element
      row.ex                # <row> element
      col.ex                # <col> element
      img.ex                # <img> element
```

Keep modules focused on a single responsibility. Cross-module dependencies should flow in one direction: `Parser → Layout → Renderer`; elements are plain data structs with no business logic.

---

## Repository Hygiene

- Run `mix format` before every commit.
- Do not commit `.elixir_ls/` or `_build/` (both are gitignored).
- Keep `mix.exs` the single source of truth for the project version and dependency list.
- Write a meaningful `@moduledoc` for every new module before merging.
