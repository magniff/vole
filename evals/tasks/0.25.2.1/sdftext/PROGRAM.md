# sdftext

Text from a signed-distance-field atlas on the GPU, and a small
immediate-mode UI (two buttons, a reset button, a slider, a text field and
a scrolling list) in the same page. The atlas is built on the CPU once at
startup from a vector font written in `glyphs.vl`: 41 glyphs (space, 0-9,
A-Z, `. - + :`), each a set of strokes. Each glyph's distance field goes into
one 512 x 384 R8 texture, and a single render pipeline draws the page's
triangles, sampling that texture with an antialiased edge.

Build and run (from this folder):

    volec main.vl -o sdftext
    ./sdftext                                  # the window
    ./sdftext --headless --shot page.ppm       # the checks, then the page as PPM
    ./sdftext --frames 120 --shot window.ppm   # the window for 120 frames, then PPM

The headless run is the way to check it without a screen. It prints the
atlas checks, a scripted run of the widgets (each checked: PASS or FAIL) and
the edge-width check, and exits 0 when all pass. Convert the image with
`python3 .../tools/ppm2png.py page.ppm page.png`.

## Controls (window)

- `-`, `+`: change the counter. `RESET` sets it back to 0.
- Slider: press and drag anywhere on the bar; it follows the pointer.
- Text box: click in it to focus, then type. Backspace deletes. Letters
  show in capitals (the font has A-Z only); characters the font lacks
  (such as `%` or `,`) draw as spaces.
- List: the mouse wheel or a trackpad scrolls it; a click selects a row.
- Close the window to quit.

## What the page shows

- Left: a title, five lines at cap heights 14 to 72 (one atlas, every size),
  and "TURN" at 0, 10, 20 and 30 degrees (the SDF is rotated per glyph).
- Right: the widgets. Under them, a readout of the slider, the counter and
  the selected row.

## What was verified, and how

- `volec test main.vl`: 4 tests (letter index mapping; the stroke's midpoint
  is inside and the cell's corner outside; the half-open hit test; a button
  clicks on release over it and not after a release elsewhere). Passes at
  -O0 and -O2.
- `./sdftext --headless`: 40 of 40 glyphs pass the atlas checks (a stroke's
  midpoint is inside, the cell's corner outside, the stroke takes 0.5% to 45%
  of the cell); the largest step between neighbouring texels is 32 of 255
  (a true distance field allows about 46); the GPU's copy of the atlas,
  read back, equals the CPU's byte for byte (196608 texels, 0 differ).
- The scripted widget run: hover makes `+` hot; two clicks make the count 2,
  a click on `-` makes it 1; a drag to 80% gives 0.800; a click in the text
  box, typing "vole sdf" and Backspace gives "vole sd"; a 3-line wheel and a
  click select row 11.
- Crispness: the edge band of an `I` stem (pixels between 12% and 88% of the
  range) is 2 px at 12, 40 and 120 px glyph sizes.
- The windowed mode was run for 60 frames through `gpu-run` (the display was
  asleep, so the frames came from the 10 fps timer); its PPM matches the
  headless layout at the window's scale of 2 (1600 x 1160 pixels). Pointer
  and key input in the window were not exercised by hand (no screen was
  shown to a person); the same input code runs in the headless script.
