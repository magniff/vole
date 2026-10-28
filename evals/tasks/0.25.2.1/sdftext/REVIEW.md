> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: sdftext (SDF text atlas and immediate-mode UI)

## 1. Reproduce
`volec main.vl -o sdftext` printed ok, and `volec test main.vl` gave `4 passed (-O0 and -O2 agree)`. No `unsafe`. Through `gpu-run --timeout 120` at load 23, `./sdftext --headless --shot page.ppm` exited 0 with `all checks pass: 0 failures`:
- Atlas: `40 of 40 glyphs pass`, `largest step ... 32 of 255`, `196608 texels read back ... 0 differ`.
- Widgets: count 2 then 1, slider 0.800, field `"vole sd"`, row 11.
- Edge band: `2 px at 12, 2 px at 40, 2 px at 120`.
- The atlas built in 42 ms (claimed 10-25; load).

page.ppm is byte-identical to the agent's. The page renders crisp stroke-font text from 12 to 72 px, four rotated "TURN" lines, buttons, a slider at 80, the field and a scrolled list with row 11 highlighted.

## 2. Claims vs reality
All claims reproduce. Two small points:
- "a true distance field allows about 46" is loose. With SPREAD = 4 texels, one texel of distance is 255/8 ≈ 32, which is exactly the measured maximum for the horizontal neighbours it checks. The figure 46 is the diagonal (√2·32).
- "41 glyphs" versus "40 of 40 pass" is consistent: the space is excluded.

The HiDPI snapshot bug it found and fixed, and the untested live input, are both reported.

## 3. Task coverage
- SDF atlas built at startup from a hand-written vector font: done (41 glyphs, CPU).
- Crisp text at any scale and rotation: done (`fwidth` antialiasing, per-line rotation).
- Buttons, slider, text field, scrolling list reacting to mouse and keyboard: done. They are scripted headless; the window input was never driven.
- Headless page at several sizes to PPM, plus atlas checks: done, and more than asked (GPU readback equality, edge width).

## 4. Correctness of the core
- The SDF is right: distance to a segment minus the half stroke width, mapped to 0.5 at the edge (atlas.vl:86-117). A spread of only 4 texels is enough for crisp edges but leaves no room for outlines or glow.
- The shader's `smoothstep(0.5-w, 0.5+w, d)` with `w = fwidth(d)` is standard. Without mipmaps, small sizes rely on `fwidth` widening, and the 14 px text still reads well.
- Rotation maths (draw.vl:155-161) is correct for y-down.
- Clipping cuts UVs proportionally for axis-aligned quads only.
- The widget logic (hot/active/focus, release-over-button click) is correct and tested.
- The checks are meaningful:
  - GPU-versus-CPU atlas equality tests the R8 upload.
  - The edge-band measure is a real crispness test through the GPU.
  - The widget script drives the same `Demo::frame` as the window.
- Not checked: that the right glyph appears where expected, and anything about rotated text.

## 5. Code quality
The best module structure of the five: glyphs, atlas, draw, gfx, ui and demo, each with a clear header comment. Immediate-mode UI state is plainly `inout`. It uses std math (`cos`, `sin`, `clamp`, `floor`, `round`, `f64::consts::PI`) and `std::clamp`/`std::abs` for integers. Nits:
- `PAIRS = 308` is hand-counted (glyphs.vl); `STROKES.len() / 2` would not drift.
- `glyph_distance` builds a copy of each `Seg` (atlas.vl:104).
- `report` rebuilds the outline.
- `MARGIN = 8.0/48.0` duplicates PAD/SCALE.
- `format_in` runs per list row per frame.

## 6. Borrowing
- `Gfx::snapshot_in` (gfx.vl:102-122) is fluid2d's `snapshot_in`.
- The CLI and window-loop shapes follow fluid2d.
- Everything else is original.

## 6b. New features
`map_read_copy_in` for the atlas readback (gfx.vl:130). MRT and depth-only do not apply. Std math is used throughout.

## 6c. Compiler bug
Not hit. The shader is `let`-bound (gfx.vl:59).

## 7. Tests
Four unit tests: glyph index mapping, stroke inside / corner outside, half-open `inside`, and button click semantics. The headless script adds 9 PASS/FAIL checks, which is good coverage of the UI logic and of the GPU upload. Missing: slider and list unit tests outside the script, live input (the HiDPI bug was found only by eye), and glyph placement.

## 8. Verdict
A complete, clean and genuinely tested result. The vector font, SDF atlas, crisp scalable and rotatable text and four working widgets were all verified by checks that could fail. The code is well organised and idiomatic. The report is accurate, specific and self-critical.

**Grades:** result **A**, code **A-**, honesty **A**.
