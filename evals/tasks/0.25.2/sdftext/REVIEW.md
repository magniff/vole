> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator, who confirmed the K glyph's definition at glyphs.vl:48.

# Review: sdftext

## 1. Reproduce
- Build ok, check 0 errors, `volec test main.vl`: 9 passed.
- `gpu-run --timeout 60 -- ./sdftext --headless --shot $S/sdf.ppm` (1.3 s): `atlas: 42 glyphs, values 0 .. 0.71`, then 8 × `PASS`, `frame: 1600x1200, 1704 vertices`, exit 0.
- I converted and read the shot, and zoomed two regions (section 4).
- The window was not run.

## 2. Claims vs reality
The checks, counts and values reproduce exactly.

Overstated: "the text is sharp at each size, the rotated banner edges are clean". The shot it inspected has two visible defects (section 4).

Otherwise candid. The windowed mode is marked unverified, and the limits are listed (no scissor, capitals only). The no-scissor limit is a design choice; std does have `RenderPass::set_scissor`.

## 3. Task coverage
- SDF atlas built at startup from a self-written vector font: **done** (42-glyph stroke font, exact distance-to-segment per texel).
- Crisp text at any scale and rotation: **done** (5 sizes plus a rotating banner; fwidth anti-aliasing).
- Buttons, slider, text field, scrolling list: **done**.
- Mouse and keyboard: **done** in code, with the logic proven by a scripted headless session through the same `build`; not checked live.
- Headless page at several sizes to PPM plus an atlas check: **done**.

## 4. Correctness of the core
The field is right:
- `0.5 − (d − half_stroke)/2` is a true signed distance to the stroked outline (`glyphs.vl:171-189`), peaking at 0.71 on the centreline.
- The shader's manual bilinear sample from a storage buffer, with `smoothstep(0.5±0.75·fwidth)`, is a sound SDF renderer (`gfx.vl:26-43`).
- Mouse coordinates in pixels are divided by the display scale (`main.vl:267`), which matches the `guide window` units.

Two bugs show in its own shot:
- **A thin vertical line is drawn left of some glyphs.**
  - Solid rectangles are marked by `u < 0` (`typeset.vl:68`, `gfx.vl:43`).
  - Glyphs in atlas column 0 (A, Q, 6: slots 0, 16, 32) have u0 = 0 at their left edge (`typeset.vl:74-78`).
  - Interpolated u dips slightly below 0 on some pixel positions, and the pixel is drawn as a solid rectangle.
  - It is visible left of "ABC" in the 18-unit line and left of "6" in "ITEM 6".
  - Fix: mark solids with u < −0.5, or a separate flag.
- **The K glyph is wrong.** `'K' => "00 08 | 80 04 | 40 88"` (`glyphs.vl:48`) starts the leg at the top middle (4,0) instead of the arm's junction. It is visible in "CLICK" and "PICK".

Minor:
- The atlas size is hard-coded in WGSL (`gfx.vl:27-29`).
- The readback row stride `bpr = 6400` (`main.vl:194`) and the `WIDTH * 2` next to `SCALE` are duplicated magic numbers.
- At small sizes, minification without mipmaps will alias.

## 5. Code quality
The best-structured of the five:
- glyphs (font and atlas), mathx, typeset (vertices and placement), gfx (pipeline), ui (immediate-mode widgets), page (layout and state), main (window and headless script).
- Widgets are pure functions of `Ui`, with `inout` state used correctly. No `unsafe`.
- Hand-rolled `sqrt` and `sin_cos` (`mathx.vl`), as expected.
- Small smells:
  - A `Buf` is allocated per visible list row per frame (`ui.vl:230`).
  - Two tests take an unused `gpa` (`let _ = gpa;`).
  - Hand-rolled argument parsing instead of `std::cli` (works).

## 6. Borrowing
- It read fluid2d's `font.vl` and `ui.vl` for shape.
- The code is original: a different font approach (an SDF of strokes versus a bitmap) and its own immediate-mode design.

## 7. Tests
- **The nine tests:** glyph slots, segment parsing, field values, sqrt and sin/cos, vertex counts, rotation about an anchor, the atlas width, and the headless script.
- **The headless script is a real behavioural test:** click, drag, typing with backspace, unfocused typing, wheel scroll, row select.
- **The script's own test is weak.** `the_headless_script_is_the_widgets_contract` ignores `script()`'s bool and asserts only `count == 1` (`main.vl:349`).
- **No check would catch a malformed glyph or a render artifact.** The atlas check accepts any inked share between 0.2% and 50%.

## 8. Verdict
An attractive, well-engineered SDF text and UI demo with a testable immediate-mode core. It falls short of top marks on the two visible rendering bugs that its own inspection missed, and the unverified window.

**Grades:** result **B+**, code **A-**, honesty **B+**.
