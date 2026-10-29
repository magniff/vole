# sdftext

Text from a signed-distance-field glyph atlas, and a small immediate-mode
UI (a button, a slider, a text field, a scrolling list) on the GPU.

- The glyphs are a vector description: a stroke font (`font.vl`), 51
  glyphs (digits, capitals, and some punctuation; lowercase is drawn as
  capitals). No bitmap is rasterised.
- At startup the CPU builds the atlas (`atlas.vl`): for every glyph, the
  exact distance from each texel to the nearest stroke, minus the stroke's
  half width, stored as 8 bits (0.5 on the outline). A 1536 x 384 R8 texture,
  96-texel cells. About 40 ms.
- Text is placed glyph by glyph on the CPU (`canvas.vl`), turned about its
  origin, so any size and any angle is one quad per glyph. The shader
  (`shaders.vl`) thresholds the field with `fwidth`, so the edges are
  computed at the frame's own resolution.
- Widgets (`ui.vl`) are immediate mode: `button`, `slider`, `field`, `list`.
  Their state (clicks, slider value, text, selection, scroll) lives in `Ui`.
  Input arrives as `Ev` values, so the headless check drives the same code.
- `render.vl`: one pipeline, alpha blending, one vertex buffer rewritten each
  frame. `main.vl`: the window, the headless script and checks.

## Run

    volec main.vl -o sdftext           # builds with std only
    ./sdftext                          # the window, 960 x 640 points
    ./sdftext --frames 120             # quit after 120 frames, print the frame time
    ./sdftext --headless --shot shot.ppm
    ./sdftext --headless --scale 2 --shot big.ppm
    volec test main.vl                 # the CPU-side tests

On the GPU, run them through the eval's lock:
`../tools/gpu-run --timeout 60 -- ./sdftext --headless --shot shot.ppm`
(`volec test` and the build need no GPU.)

## Controls

- Click ADD (counts clicks), RESET (clears the count and the text).
- Drag the slider, or press on its track.
- Click the text field and type; Backspace deletes. Clicking elsewhere
  unfocuses it.
- Wheel over the list scrolls it by rows; click a row to select it.
- Esc quits.

## What the headless run prints and checks

It checks the atlas bytes: for each glyph, the middle of its first stroke
must be above 0.5 and its cell's corner below 0.5 (both 51 of 51). It then
feeds a script of events (two ADD clicks, a slider drag to 0.75, typing
HELLO with one backspace and an O, a wheel of 6 rows and a click) through
the widgets and checks the state (clicks 2, text HELLO, list selection 8).
It renders the page to the PPM and counts the lit and edge pixels.

## Verified

- `volec test main.vl`: 7 tests (font segments, atlas bytes, button click
  on release, slider mapping and clamping, field focus and backspace, list
  clamping, text as 6 vertices a glyph), at -O0 and -O2.
- Headless: `headless.txt` (the output of the last run), `shot.png`.
- Windowed: a short run through gpu-run with `--frames 30 --shot`; the
  snapshot is 1920 x 1280 at the display's scale 2 (the window's page is
  960 x 640 points), and it shows the same page as the headless shot.
  The display was asleep in the run, so its frame times are the window's
  100 ms timer, not the GPU's.
- Not checked: interaction in a live window (clicks and keys were fed by
  the headless script, not by a person), and the frame rate.
