# ATML — Simple Template Markup Language Specification

> Version 1.0 | A declarative XML dialect for defining Airway Bill label layouts that render to PDF.

---

## Table of Contents

1. [Overview](#overview)
2. [Document Structure](#document-structure)
3. [Nesting Model](#nesting-model)
4. [Value Types](#value-types)
   - [Dimensions](#dimensions)
   - [Spacing](#spacing)
   - [Borders](#borders)
   - [Fonts](#fonts)
   - [Alignment](#alignment)
5. [Elements](#elements)
   - [`<document>`](#document)
   - [`<row>`](#row)
   - [`<col>`](#col)
   - [`<img>`](#img)
6. [Inheritance](#inheritance)
7. [Constraint Resolution](#constraint-resolution)
8. [Full Example](#full-example)
9. [Type Summary](#type-summary)

---

## Overview

ATML (AWB Template Markup Language) is an XML-based format for authoring printable Airway Bill label templates. The only layout primitives are rows and columns, enabling a predictable and unambiguous mapping to PDF output.

An ATML document describes a single label. The renderer resolves dimensions, applies font inheritance, then generates the PDF with no external stylesheet dependencies.

---

## Document Structure

Every ATML file must begin with an XML declaration followed by a single `<document>` root element.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<document width="400pt" height="600pt">

  <row>
    <col> ... </col>
    <col> ... </col>
  </row>

  <row>
    <col>
      <!-- nested row inside a col -->
      <row>
        <col> ... </col>
      </row>
    </col>
  </row>

</document>
```

---

## Nesting Model

The layout model alternates strictly between rows and columns. The valid parent–child relationships are:

```
<document>
  └── <row>
        └── <col>
              ├── text / <img>
              └── <row>              ← must interpose a row before nesting cols
                    └── <col>
                          └── text / <img>
```

**Rules:**

- `<document>` may only contain `<row>` children.
- `<row>` may only contain `<col>` children.
- `<col>` may contain text, `<img>`, or `<row>` children. Mixed content (text alongside child elements) is permitted.
- A `<col>` **cannot** be a direct child of another `<col>`. This is a parse error.

---

## Value Types

### Dimensions

Used for `width`, `height`, `min-width`, `max-width`, `min-height`, `max-height`.

| Format | Example | Description |
|---|---|---|
| Points | `100pt` | Fixed size in typographic points (1pt = 1/72 inch) |
| Pixels | `120px` | Fixed size in screen pixels |
| Percentage | `50%` | Relative to the parent container's dimension |
| `fill` | `fill` | Grow to consume all remaining space on the parent axis. When multiple siblings use `fill`, the remaining space is divided equally among them. |
| `fit` | `fit` | Shrink-wrap to the element's own content size |

> `fill` and `fit` apply to the layout axis only — width for `<col>`, height for `<row>`. The cross-axis follows the parent's computed size.

---

### Spacing

Used for `padding` and all `padding-*` properties.

- **Units:** `pt` or `px`
- **Minimum value:** `0`
- **Default:** `0`
- A unitless `0` is valid.

| Format | Example | Sides Applied |
|---|---|---|
| Single value | `4pt` | All four sides |
| Two values | `4pt 8pt` | Top & Bottom \| Left & Right |
| Four values | `2pt 4pt 2pt 4pt` | Top \| Right \| Bottom \| Left |
| Zero | `0` | All sides |

Per-side attributes (`padding-top`, `padding-right`, `padding-bottom`, `padding-left`) each accept a single value and override the corresponding side of the shorthand `padding` if both are declared.

---

### Borders

Borders may be set as an all-sides shorthand or per-side. Per-side declarations are applied after the shorthand, overriding individual sides.

**Properties:**

| Property | Scope |
|---|---|
| `border` | All four sides |
| `border-top` | Top side only |
| `border-right` | Right side only |
| `border-bottom` | Bottom side only |
| `border-left` | Left side only |

**Value format:**

Each border value is either the keyword `none`, or a three-token string:

```
"none"
"<style> <width> <color>"
```

| Token | Allowed Values |
|---|---|
| `style` | `solid` \| `dashed` \| `dotted` |
| `width` | `<number>pt` or `<number>px` — minimum `0` |
| `color` | `#rrggbb` or `#rgb` hex string |

**Examples:**

```xml
border="solid 1pt #000000"
border-bottom="dashed 1pt #cccccc"
border-top="none"
border-left="dotted 2px #aaaaaa"
```

---

### Fonts

All font attributes cascade from `<document>` → `<row>` → `<col>`. A child element uses the nearest ancestor's value unless it declares its own override.

| Attribute | Allowed Values | Default |
|---|---|---|
| `font-family` | Any font name string | `"Helvetica"` |
| `font-size` | `<number>pt` | `8pt` |
| `font-weight` | `normal` \| `bold` | `normal` |

---

### Alignment

| Attribute | Allowed Values | Default | Applies To |
|---|---|---|---|
| `text-align` | `left` \| `center` \| `right` | `left` | Horizontal alignment of text content |
| `vertical-align` | `top` \| `center` \| `bottom` | `top` | Vertical alignment of content within the element |

---

## Elements

### `<document>`

The root element. Defines the physical dimensions of the label canvas. Exactly one per document.

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `width` | dimension | **required** | Physical document width |
| `height` | dimension | **required** | Physical document height |
| `padding` | spacing | `0` | Outer inset applied to all direct child rows |
| `font-family` | string | `"Helvetica"` | Inherited by all descendants |
| `font-size` | pt | `8pt` | Inherited by all descendants |
| `font-weight` | `normal` \| `bold` | `normal` | Inherited by all descendants |

---

### `<row>`

A horizontal container. Children are laid out left to right. Rows stack vertically within their parent (`<document>` or `<col>`).

**Valid children:** `<col>` only.

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `height` | dimension | `fit` | Use `fill` to consume remaining parent height |
| `min-height` | dimension | — | Floor constraint on computed height |
| `max-height` | dimension | — | Ceiling constraint on computed height |
| `width` | dimension | `fill` | Typically fills parent width |
| `padding` | spacing | `0` | Inner padding |
| `padding-top` | spacing | — | Per-side override |
| `padding-right` | spacing | — | Per-side override |
| `padding-bottom` | spacing | — | Per-side override |
| `padding-left` | spacing | — | Per-side override |
| `border` | border | — | All-sides border |
| `border-top` | border | — | Top side override |
| `border-right` | border | — | Right side override |
| `border-bottom` | border | — | Bottom side override |
| `border-left` | border | — | Left side override |
| `vertical-align` | `top` \| `center` \| `bottom` | `top` | Default vertical alignment for child col content |

---

### `<col>`

A vertical cell within a `<row>`. Columns are laid out horizontally within their parent row.

**Valid children:** text, `<img>`, `<row>`. Mixed content is allowed. A `<col>` cannot be a direct child of another `<col>`.

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `width` | dimension | `fit` | Column width within the parent row |
| `min-width` | dimension | — | Floor constraint |
| `max-width` | dimension | — | Ceiling constraint |
| `height` | dimension | `fill` | Height relative to the parent row |
| `padding` | spacing | `0` | Inner padding |
| `padding-top` | spacing | — | Per-side override |
| `padding-right` | spacing | — | Per-side override |
| `padding-bottom` | spacing | — | Per-side override |
| `padding-left` | spacing | — | Per-side override |
| `border` | border | — | All-sides border |
| `border-top` | border | — | Top side override |
| `border-right` | border | — | Right side override |
| `border-bottom` | border | — | Bottom side override |
| `border-left` | border | — | Left side override |
| `font-family` | string | inherited | Font family override |
| `font-size` | pt | inherited | Font size override |
| `font-weight` | `normal` \| `bold` | inherited | Font weight override |
| `text-align` | `left` \| `center` \| `right` | `left` | Horizontal text alignment |
| `vertical-align` | `top` \| `center` \| `bottom` | `top` | Vertical alignment of content |

---

### `<img>`

An inline image element. Must be a direct child of `<col>`.

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `src` | string | **required** | Local file path, or `base64:<data>` for embedded images |
| `width` | dimension | `fit` | Rendered image width |
| `height` | dimension | `fit` | Rendered image height |
| `min-width` | dimension | — | Floor constraint |
| `max-width` | dimension | — | Ceiling constraint |
| `min-height` | dimension | — | Floor constraint |
| `max-height` | dimension | — | Ceiling constraint |

**Scaling behavior:**

- If only one axis is fixed and the other is `fit`, the image scales proportionally preserving aspect ratio.
- If both axes are fixed, the image is stretched to fill without preserving aspect ratio.
- If both are `fit`, the image renders at its intrinsic size.

**`src` formats:**

```
src="/path/to/logo.png"
src="base64:iVBORw0KGgoAAAANS..."
```

---

## Inheritance

Font attributes cascade top-down through the element tree:

```
<document font-family="Helvetica" font-size="8pt" font-weight="normal">
  <row>                            ← inherits all font attrs from document
    <col font-size="12pt">         ← overrides font-size, inherits the rest
      <row>
        <col font-weight="bold">   ← overrides font-weight, inherits font-size 12pt
        </col>
      </row>
    </col>
  </row>
```

Non-font attributes (`padding`, `border`, `text-align`, `vertical-align`) do **not** inherit — they must be set explicitly on each element.

---

## Constraint Resolution

When `min-*` / `max-*` are combined with a base dimension, the following order applies:

1. Compute the base `width` or `height` value (resolve `%`, `fill`, `fit`)
2. Apply `min-*` as a floor — result cannot go below this value
3. Apply `max-*` as a ceiling — result cannot exceed this value
4. `fill` expansion distributes remaining space only after all fixed and `fit` siblings have been resolved and constrained

---

## Full Example

```xml
<?Xml version="1.0" encoding="UTF-8"?>
<document width="400pt" height="600pt" font-family="Helvetica" font-size="8pt">

  <!-- Header: logo + title -->
  <row height="60pt" border-bottom="solid 1pt #000000">
    <col width="80pt" vertical-align="center" text-align="center" padding="4pt">
      <img src="/assets/logo.png" width="60pt" height="40pt" />
    </col>
    <col width="fill" vertical-align="center" padding="4pt 8pt"
         font-size="14pt" font-weight="bold" text-align="center">
      AIR WAYBILL
    </col>
  </row>

  <!-- Sender / Recipient -->
  <row height="fill" border-bottom="solid 1pt #000000">
    <col width="50%" padding="6pt" border-right="solid 1pt #000000">
      <row height="fit">
        <col font-weight="bold" font-size="7pt">SENDER</col>
      </row>
      <row height="fill">
        <col padding-top="4pt">John Doe, 123 Street, Ho Chi Minh City</col>
      </row>
    </col>
    <col width="fill" padding="6pt">
      <row height="fit">
        <col font-weight="bold" font-size="7pt">RECIPIENT</col>
      </row>
      <row height="fill">
        <col padding-top="4pt">Jane Smith, 456 Avenue, Hanoi</col>
      </row>
    </col>
  </row>

  <!-- Parcel details row -->
  <row height="40pt" border-bottom="solid 1pt #000000">
    <col width="33%" padding="4pt 6pt" border-right="solid 1pt #000000">
      <row height="fit">
        <col font-weight="bold" font-size="7pt">WEIGHT</col>
      </row>
      <row height="fill">
        <col vertical-align="center">2.5 kg</col>
      </row>
    </col>
    <col width="33%" padding="4pt 6pt" border-right="solid 1pt #000000">
      <row height="fit">
        <col font-weight="bold" font-size="7pt">DIMENSIONS</col>
      </row>
      <row height="fill">
        <col vertical-align="center">30 x 20 x 15 cm</col>
      </row>
    </col>
    <col width="fill" padding="4pt 6pt">
      <row height="fit">
        <col font-weight="bold" font-size="7pt">SERVICE</col>
      </row>
      <row height="fill">
        <col vertical-align="center">Express</col>
      </row>
    </col>
  </row>

  <!-- Barcode -->
  <row height="80pt" border-bottom="dashed 1pt #aaaaaa">
    <col text-align="center" vertical-align="center" padding="8pt">
      <img src="base64:iVBORw0KGgoAAAANS..." width="fill" height="60pt" />
    </col>
  </row>

  <!-- Tracking number -->
  <row height="28pt">
    <col text-align="center" vertical-align="center"
         font-size="11pt" font-weight="bold">
      VN-123456789-SG
    </col>
  </row>

</document>
```

---

## Type Summary

| Type | Format | Examples |
|---|---|---|
| **Dimension** | `<n>pt` \| `<n>px` \| `<n>%` \| `fill` \| `fit` | `100pt`, `50%`, `fill`, `fit` |
| **Spacing** | single / two / four value, units `pt`/`px` | `4pt`, `4pt 8pt`, `2pt 4pt 2pt 4pt` |
| **Border** | `none` or `<style> <width> <color>` | `solid 1pt #000`, `dashed 2px #aaa`, `none` |
| **Border style** | keyword | `solid`, `dashed`, `dotted` |
| **Font size** | `<n>pt` | `8pt`, `12pt` |
| **Font weight** | keyword | `normal`, `bold` |
| **Text align** | keyword | `left`, `center`, `right` |
| **Vertical align** | keyword | `top`, `center`, `bottom` |
| **Image src** | path or base64 | `/path/to/file.png`, `base64:<data>` |
