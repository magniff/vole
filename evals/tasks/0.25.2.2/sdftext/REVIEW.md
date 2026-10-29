> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: sdftext

## 1. Reproduce
`volec main.vl -o sdftext`: ok. `volec test main.vl`: `7 passed (7 #[test]; -O0 and -O2 agree)`. Through `gpu-run --timeout 60`:
- `./sdftext --headless --shot shot.ppm`, exit 0. Output identical to `headless.txt`: atlas 51/51 and 51/51; `widgets: clicks 2, value 0.75, text "HELLO" (5 bytes), list top 6, selected 8`; 1770 vertices. The atlas time was 73.3 ms here, against 40.7 ms reported (load).
- `--scale 2 --shot big.ppm` also passes.
- The page is crisp at 12–96 px and rotated: title, sizes, tilted text, buttons, slider at 75, field "HELLO", list with CRANBERRY selected.

## 2. Claims vs reality
- All claims hold, and the limits are stated honestly: live interaction was not exercised, the window frame time is meaningless, and the lit-pixel counts are not a test.
- Two nuances:
  - "Checks the atlas" checks a second CPU build (main.vl:152), not the uploaded texture. The atlas is built twice; the first build is inside `Renderer::new_in` (render.vl:35).
  - "Exact distance" is true, but the stored value tops out at 0.75 on the centre line (atlas.vl:50).

## 3. Task coverage
- SDF atlas built at startup from its own vector font: done (51 straight-stroke glyphs, capitals only).
- Crisp text at any scale and rotation: done (`fwidth` threshold, CPU rotation).
- Buttons, a slider, a text field, a scrolling list reacting to mouse and keyboard: done, through a shared `Ev` path. Only the scripted headless input was exercised.
- Headless page at several sizes to PPM, and an atlas check: done; the check is weak.

## 4. Correctness of the core
- The atlas (atlas.vl:27-74) is the exact point-segment distance minus the half width, mapped to 0..1 over a 14-unit spread. The 20-unit cell margin keeps neighbours below 0.5, so linear sampling at cell edges does not bleed.
- The shader (shaders.vl:18-23) uses `smoothstep(0.5 ± 0.75·fwidth)`: the standard screen-space antialiasing.
- Glyph quads span the whole 140-unit cell with an 80-unit advance, so quads overlap. With alpha blending their transparent margins are harmless.
- The immediate-mode logic is correct: press-and-release on the same widget, an active-widget slider drag, focus on press, whole-row wheel scrolling with clamping.
- Defects:
  - Characters missing from the font are silently skipped. The page itself uses commas (ui.vl:259, 284, 288), which render as double spaces in the shot.
  - "TILTED -20" is drawn at +0.3 rad, about +17° (ui.vl:265).
  - The atlas check (main.vl:70-96) samples the midpoint of the first segment (about 0.75 by construction) and the cell's corner texel (always far from strokes). It can only catch gross layout bugs.
  - `widgets_ok` (main.vl:156) checks only the text length (5), not "HELLO", and ignores the slider value.
- One GPU pipeline and one vertex buffer rewritten per frame. `write_buffer` while in flight is staged by std, so this is correct.

## 5. Code quality
- A good module split: font, atlas, canvas, render, ui, shaders, main. `Ev` as an input abstraction is a nice design that lets the headless script drive the real widgets.
- Small items:
  - A stale comment says "gpu.vl: the pipeline" (main.vl:12).
  - `script`'s doc says it returns events; it returns nothing. Its `let s = scale` is unused (main.vl:99-101).
  - `check_atlas` duplicates the `#[test]` at atlas.vl:79-93 almost line for line.
  - `clamp_i` (ui.vl:293) duplicates the integer `clamp` that std now has.
  - `Ui` carries a `gpa` only to format labels; that is the language's cost, and the report flags it.
- No `unsafe`.

## 6. Borrowing
- `snapshot` (main.vl:43-65) and the window loop come from fluid2d. The report says so ("copied almost whole").
- The font, atlas, canvas and widgets are original. fluid2d's font is a 5x7 bitmap with nothing in common.

## 6b. New in 0.25.2.2
- One module and one pipeline, so module sharing does not apply.
- R8Unorm atlas texture.
- `clamp_i` should have been the integer `clamp`.
- No uniform buffer, so `gpu.unwritten` is irrelevant. No `adapter.limits()`.

## 6c. Mapped view across a submit
None. The view in `snapshot` ends before any later submit.

## 7. Tests
- Seven tests: font parse, atlas bytes, button release semantics, slider clamp, field focus and backspace, list clamp, six vertices per glyph. Together with the scripted headless run they give real coverage of the UI logic.
- Missing:
  - a GPU readback of the atlas;
  - a glyph advance/overlap check (the double-scale bug the agent hit was caught only by eye);
  - detection of missing glyphs;
  - the window's event mapping (scroll sign, Text events).

## 8. Verdict
A working, good-looking SDF text and immediate-mode UI demo with a well-chosen design (vector strokes, `fwidth` antialiasing, a shared input path), all within the task. The weak points are the near-tautological atlas check and small polish issues (dropped commas, a mislabelled angle, the duplicated atlas build). The report is detailed, accurate and self-critical.

**Grades:** result **A-**, code **B+**, honesty **A**.
