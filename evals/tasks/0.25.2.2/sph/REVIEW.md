> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: sph (2D SPH, 102,400 particles)

## 1. Reproduce
Built in a scratch copy: ok. `volec test main.vl` → 5 passed.
- `gpu-run --timeout 120 -- ./sph --headless --shot shot.ppm`, exit 0. Grid checks: `0 counts, 0 cells differ`, `0 of 40402 differ`, `0 problems`. **6000 substeps** (0.3 s of fluid): density 102.1% of rest, top speed 5.35, penetration 0.00011, `0.435 ms a substep`, `overall: grid ok, fluid ok`.
- `--steps 20000`: 101.14% of rest, last two checks 0.42% apart, ok.
- `--steps 2400 --shot`: see 4, the window question.

## 2. Claims vs reality
- **Wrong**: "Default `./sph --headless` (20,000 substeps = 1 s)" in ANALYSIS and the README's "about 20 s for the default 20,000 substeps". The default is 6000 (`main.vl:411,425`).
- The "100.7%, within 0.23%" figures came from a 20000-step run. They are not reproducible exactly, because the atomic scatter order is nondeterministic; I got 101.14% and 0.42%. Those are still within the checks.
- The grid and penetration claims hold.
- The "windowed snapshot is wrong" item is a false alarm (below), but it was honestly flagged as unresolved rather than claimed to be fine.

## 3. Task coverage
- At least 100k particles: done (102,400).
- GPU grid: done. Counting sort (clear, count with atomics, a one-workgroup Hillis-Steele scan, scatter).
- Density, pressure, viscosity, integration: done.
- Colour by speed: done.
- Tilt (arrows) and stir (mouse): done in code, not seen.
- Sort and prefix sum vs CPU: done, on the start block only.
- Density settling: done, but weak.
- No escape: done.
- Shot: done.

## 4. Correctness of the core
- **Physics**: the kernels are right. 2D poly6 is 4/(πh⁸) (`shaders.vl:136`). The spiky gradient is 30/(πh⁵)(h−r)² with a symmetric pressure term (161-191). The viscosity Laplacian is 40/(πh⁵)(h−r), and the pressure is clamped to ≥0.
- **Scan**: correct (barriers on both sides of each step). The sort is verified structurally (`main.vl:84-107`).
- **The windowed "bug" is the program behaving correctly.** At 2560×1440 with zoom 1.84 and aspect 1440/2560, the transform puts box x = 0 at 618 px and the floor at y = 1382 px. In `window.png` the fluid's left edge is at about 614 px and its bottom at 1382: exactly right. The window steps 20 substeps a frame (`main.vl:339`), so 120 frames are 2400 × 5e-5 = **0.12 s** of fluid, against 0.3 s or 1 s for the headless shots. At 0.12 s the dam break has barely started: the block (x 0.03–0.67) still sits in the lower left of an *undrawn* box, so it reads as "off-centre". Its top has dropped about 0.06 box units (½gt² = 0.07), so it looks squashed.
- **The yellow band**: the lattice starts at exactly rest density, so pressure is 0 everywhere and nothing supports the column. The top layer free-falls uniformly at g·t ≈ 1.2 units/s, which is 0.8 on the speed ramp (vref 1.5), i.e. uniform orange-yellow above the V-shaped pressure front.
- I confirmed this headless: `--steps 2400 --shot` at 720×720 gives the same picture, with the same V front and the same band. This is neither the program's mapping nor std::window/std::gpu; HiDPI units are handled correctly (`main.vl:278,286,335`). The real lessons are to draw the box, to give the start a hydrostatic profile, and that 20 substeps a frame makes the window run at about 0.06× real time (0.44 ms × 20 ≈ 9 ms GPU a frame).
- **Weak checks**:
  - "Settled" passes at 0.3 s with top speed 5.35 units/s (the fluid is sloshing). It needs a kinetic or velocity criterion.
  - "All inside" cannot fail except through NaN, because INTEGRATE clamps positions (`shaders.vl:227-230`). The penetration-below-h test is the meaningful part.
  - The grid check runs only on the regular start lattice, not after motion.
- **Minor**: `sz` is captured once (`main.vl:278`), so the mouse mapping and aspect go stale after a resize.

## 5. Code quality
The split is good: `geom.vl` holds the pure functions and tests, `sim.vl` the GPU side, `shaders.vl` the WGSL. Naming and comments are clear. There is no `unsafe` and no dead code. Hand-rolled items: `clamp_i` (`geom.vl:112`), where `i64.clamp` exists since 0.25.2.2; `PI` (`geom.vl:23`); and `3.14159265` for deg→rad (`main.vl:434`). The `f32_bits_to_f` wrapper (`main.vl:238`) is redundant.

## 6. Borrowing
`kernel()` is the guide's helper, `snapshot_in` is fluid2d's, and the window loop follows fluid2d's shape. The scan is the voxel example's idea (Hillis-Steele), written afresh.

## 6b. New in 0.25.2.2
Integer `clamp` was not used (see 5). It uses one module per kernel and does not call `adapter.limits()`; the dispatches stay under 65535 (1600 groups at the default size, up to 15625 at `--side 1000`). The uniform is written by `set_knobs` before every submit, so `gpu.unwritten` did not fire.

## 6c. Mapped views
All views (`check_grid`, `density_stats`, `motion`, the final `pos`/`penmax`) are read and dropped before the next submit. No dependency.

## 7. Tests
There are 5 unit tests: poly6 normalisation, the scan, gravity under tilt, the screen↔box round trip, and cell coverage. They are relevant, though the round-trip test is the only coverage of the view mapping, and it passed (the mapping is right). Missing: a grid check after motion, a real settling criterion, and a picture at the window's time step.

## 8. Verdict
This is a solid GPU SPH with an exactly verified counting sort and stable physics. The agent's physics debugging (stiffness c², the negative poly6 Laplacian, the viscosity bound) is good work, though most of its 29 minutes went there. The windowed "bug" is a misdiagnosis: it compared a 0.12 s frame with a 0.3–1 s frame. The report misstates the default run length.

**Grades:** result **B+**, code **B+**, honesty **B**.
