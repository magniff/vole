> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator, who confirmed `use std::gpu::wgsl::uniformity::check;` is still at main.vl:20.

# Review: deferred

## 1. Reproduce
- Build ok, check 0 errors, `volec test main.vl`: 3 passed.
- `gpu-run --timeout 120 -- ./deferred --headless --frames 300 --check --shot $S/df.ppm` (load 20.5):
  - `512 lights, 41 objects, 1280x720, 300 frames: 1.4806933333333332 ms a frame`
  - `culling: 64779 pixels, 410988 lit-by pairs, 0 missed, most lights in a tile 126 (average 58), 0 tiles over 256`
  - Four PPMs written, exit 0.
- The lit frame, normals and depth look right: coloured light pools, flat-shaded cube faces, near is white.
- The window was not run.

## 2. Claims vs reality
The culling numbers reproduce exactly; frame time is 1.48 ms against the claimed 1.35 (load). The unverified windowed mode is stated plainly.

Misstatements:
- **The bogus auto-fix import is not removed.** It says it removed `use std::gpu::wgsl::uniformity::check;`, but it is still at `main.vl:20`.
- **The path does exist.** It is std-internal (`compiler/std/gpu/wgsl/uniformity.vl:6`), not "a path that does not exist".
- `volec check` does not flag the import as unused, because the parameter `check: bool` (`main.vl:123`) shadows it. That is a tooling gap worth recording.

The MRT complaint is accurate:
- `PassDesc` has one `color` attachment (`std/gpu/mod.vl:1151`), although `RenderDesc::target()` allows up to 8 pipeline targets.
- So three geometry passes is a std gap, not agent laziness.

## 3. Task coverage
- Generated meshes (cubes, spheres, floor): **done** (generated on the GPU by `GEN`).
- G-buffer into several targets: **partial**. Albedo, normal and world position plus view depth are drawn in 3 passes because of the std limit.
- At least 256 moving coloured point lights: **done** (512).
- Compute light culling: **done**. 16×16 screen tiles, no per-tile depth bounds, hence about 58 lights per tile.
- Tone mapping: **done** (ACES fit, gamma 2.2).
- Keys toggle the G-buffer views: **written**, not verified.
- Headless views plus frame time: **done**.

## 4. Correctness of the core
- **Camera and projection are correct.** The view matrix is exact and correct (`scene.vl:105-110`). The projection is the correct right-handed [0,1] depth form (A = −f/(f−n), B = −fn/(f−n)).
- **Normals are correct** for non-uniform scale (`n/scale`, `shaders.vl:187`).
- **The cull is conservative and correct.** It projects the 8 corners of the light sphere's view-space box when the whole box is in front of the near plane, otherwise keeps the light (`:140-157`). It resets the tile counter with an atomic store plus barriers inside the workgroup that owns the tile (`:128-132`).
- **Pass order is right.** Update → cull → G-buffer → lighting in one encoder; the lighting pass clamps the count to MAXL (`:235`).

The `--check` is the best verification of the five. It is an independent CPU oracle: every light whose sphere contains a sampled G-buffer position must be in that tile's list. It caught a real bug in the first, projected-disc cull. It does not measure how tight the lists are.

## 5. Code quality
- Clear modules; the `Screen` struct is rebuilt on resize; `sink`, `inout` and `?` are idiomatic. No `unsafe`.
- Constants are duplicated between WGSL and `scene.vl` (`TILE`, `MAXL`), but with a comment saying so.
- Smells:
  - Dead `verts_bytes` (`scene.vl:135`).
  - The stale import.
  - `{ms}` printed unformatted.
  - `geo_pipe` compiles the same GEO module three times (`render.vl:67`).
- No hand-rolled math: trig moved to WGSL and the camera made exact, a neat dodge.

## 6. Borrowing
- `read_ppm`'s BGRA-to-PPM loop matches fluid2d's `snapshot_in`.
- The full-screen triangle is the guide's.
- Everything else (cull, G-buffer, mesh generation) is original.

## 7. Tests
- **The three `#[test]`s are thin:** view matrix, RNG, record lengths.
- **The GPU culling check carries the verification.**
- **Missing:** a projection test, a G-buffer content check (for example floor normal = +y), and the windowed key path.

## 8. Verdict
A solid deferred renderer with a genuinely rigorous culling check. It falls short of one-pass MRT only because of std. The report's main points are accurate and useful (the MRT gap, no GPU timestamps), but it misreports its own fix of the auto-imported `check`.

**Grades:** result **B+**, code **B+**, honesty **B**.
