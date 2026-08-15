---
name: drawio-paper-figure
description: Create or refine editable, publication-ready academic figures as native draw.io files. Use for paper diagrams, method or system overviews, model architectures, workflows, scientific visualizations, graphical abstracts, and iterative edits to existing `.drawio` figures from prose, ASCII sketches, manuscripts, or reference figures.
---

# Academic Paper Figures

Create clear, restrained, fully editable figures with equal attention to scientific correctness and visual consistency.

## Workflow

1. Read referenced `.drawio` files first; reuse exact terminology and requested visual conventions.
2. Extract only content intended for the figure, including required labels, relations, formulas, and annotations.
3. Infer a sensible layout; ask one concise question only when ambiguity changes the scientific meaning.
4. Use `image_gen` for a new figure only when a raster composition study materially helps. Edit clear schematics directly in draw.io.
5. Build native mxGraph XML with independently editable labels, shapes, frames, and connectors.
6. Validate semantics, consistency, XML structure, and layout before delivery.

Never modify a reference when the user asks for a new file. During edits, preserve unrelated content and make the smallest coherent change.

## Visual System

- Use a fresh, light, low-saturation palette on white or near-white; prefer thin strokes, square corners, whitespace, and limited decoration.
- Follow a reference palette when provided. Otherwise assign a small set of accents by meaning and keep the mapping stable.
- Use one font family. Default to `11-12 pt` body, `10 pt` hints, `16-18 pt` section headings, and `22-24 pt` title.
- Keep repeated semantic elements identical in font, color, stroke, size, and alignment unless a declared quantity controls size.
- Align related rows and columns to shared anchors; use consistent gaps, row heights, and margins.
- Keep group frames thin, close to their contents, and clear of neighboring groups.
- Use color as a secondary cue; structure and labels must remain understandable without it.

Default accents: blue `#DCE8F5/#87A9C9/#294B6B`, sage `#E4EAD8/#A7B890/#435437`, peach `#F0D8D5/#D49B95/#7C4842`, lavender `#E9DDF0/#B89BC9/#624A72`, yellow `#FFF2CC/#D6B656/#663300`, neutral `#F3F4F6/#CBD3DD/#667485`.

## Information Fidelity

- Preserve exact terminology, symbols, units, indices, and capitalization from the source.
- Distinguish schematic structure from quantitative encoding; never infer measurements from counts, dimensions, spacing, or color without support.
- Mark ambiguous geometry as not to scale or use symbolic values instead of invented numbers.
- Preserve names, colors, indices, and hierarchy when the same entities appear in multiple views; show mappings when order changes.
- Aggregate repetition only when no required information is hidden, and never attach unsupported quantities.
- Give matrices, tables, charts, and comparisons aligned labels and a consistent declared scale or color convention.

## Draw.io Requirements

- Produce native `.drawio` mxGraph XML, not Mermaid, CSV, or a flattened raster.
- Include root cells `id="0"` and `id="1"`; place normal elements under `parent="1"` unless layers are intentional.
- Give each `mxCell` a unique ID and each edge an `mxGeometry relative="1"` child with explicit arrow styling.
- Use native connectors instead of text glyphs; keep edge labels separate and route connectors to reduce crossings.
- Keep text editable, labels concise, and line styles semantically consistent.
- Use native math rendering for equations rather than ASCII approximations.
- Use icons sparingly; prefer editable vectors and verify licenses for external assets.
- Use lowercase hyphenated filenames and escape XML attribute characters correctly.

## Validation

- Parse XML with `xmllint` or an equivalent parser; check root cells, unique IDs, edge geometry, and arrow usage.
- Verify labels, symbols, units, relationship direction, quantitative encodings, and cross-view mappings.
- Check repeated styles, alignment, spacing, crossings, clipping, and overlaps.
- Export and inspect a preview when possible; if export fails, complete structural validation and report it only when preview delivery was requested.

Deliver the editable `.drawio` file and briefly state material assumptions or validation limits.
