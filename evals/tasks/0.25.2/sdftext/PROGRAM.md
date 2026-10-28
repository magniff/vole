# sdftext

Text from a signed-distance-field atlas, on the GPU, and a small
immediate-mode UI on it: two buttons, a slider, a text field and a
scrolling list, all driven by the mouse and the keyboard.

- The glyphs are a stroke font I wrote (`glyphs.vl`): 42 characters
  (A-Z, 0-9, space and `. - + : / !`), each a few line segments on an
  8 x 8 grid. Lowercase input is drawn as capitals.
- At startup the CPU computes each glyph's distance field into a 48 x 48
  cell of a 768 x 192 f32 atlas (`glyphs.vl`, `build_atlas`).
- The render shader (`gfx.vl`) samples the atlas bilinearly, takes the
  0.5 level as the edge and smooths it with the screen derivative, so the
  outline stays sharp at any size and rotation.
- Vertices are built on the CPU (`typeset.vl`: text, rectangles, a
  placement with scale and rotation); the widgets are in `ui.vl`; the
  page's layout and state are in `page.vl`; `main.vl` has the window loop
  and the headless script.
- `mathx.vl` has the square root and sin/cos the demo needs, in plain
  vole (Newton's iteration, Taylor series). No C calls, no `unsafe`.

## Build and run

```
volec main.vl -o sdftext
./sdftext                       # the window (Esc quits)
./sdftext --frames 120          # the window, quits after 120 frames
./sdftext --headless            # scripted checks, exit 0 when all pass
./sdftext --headless --shot shot.ppm   # and the frame as a PPM (1600 x 1200)
volec test main.vl              # the #[test]s (glyph, math, layout, script)
```

Headless runs through the GPU lock:
`tools/gpu-run --timeout 60 -- ./sdftext --headless --shot shot.ppm`.

## Controls

- Click CLICK +1 to count, RESET to zero the count.
- Drag the slider to set the size of the rotating ROTATE banner.
- Click the text field to focus it, then type; Backspace deletes.
  Clicking elsewhere takes the focus away.
- Scroll the wheel (or trackpad) over the list; click a row to select it.
- Esc quits.

## What it shows

The page sets a line of capitals and digits at five sizes (8 to 40
logical units of cap height), and the banner turns continuously about
its centre, its size set by the slider. The
window renders at the display's scale (2x on Retina).

## What I verified, and how

- `volec test main.vl`: 9 tests, passing at -O0 and -O2. They cover the
  glyph slots, the segment parser (a dot is one segment), the field
  values (0.5 on an edge, above it inside a stroke, 0 far away), square
  roots and sin/cos, the vertex counts of text and rectangles, rotation
  about an anchor, and the headless widget script.
- `./sdftext --headless` (through gpu-run; 1600 x 1200 frame):
  - atlas: 42 glyphs, every one with an inked share between 0.2% and
    50% of its cell (`PASS atlas: ...`), field values from 0 to 0.71;
  - widgets, driven by scripted events through the same `build` the
    window uses: one click on CLICK +1 counts 1; dragging the slider to
    80% sets it to 0.80; focusing the text field and typing `hello` with
    one backspace gives `hell`; a text field that is not focused takes no
    typing; a two-row wheel scroll gives a scroll of 52; a click selects
    the row under the pointer (row 3).
  All eight checks print PASS and the program exits 0.
- I opened the PPM, converted it to PNG (`tools/ppm2png.py`) and looked at
  it: the text is sharp at each size, the rotated banner edges are clean,
  and the widgets lay out without overlap.
- The windowed mode was not verified: a `--frames 120` run under gpu-run
  did not return and was killed at 60 s (see ANALYSIS.md). The window
  code compiles and shares the frame path with the headless mode.

## Limits

- The list hides rows that are only partly inside its box (no scissor).
- The text field keeps 40 characters and shows capitals only.
- No rounded corners on the widgets; the frame is a 1-unit border.
- The atlas is rebuilt on every start (the build is on the CPU, not
  timed).
