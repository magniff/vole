> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: deferred (G-buffer, tiled culling, 512 lights)

## 1. Reproduce
`volec main.vl -o deferred` printed ok, and `volec test main.vl` gave `5 passed (-O0 and -O2 agree)`. No `unsafe`. Through `gpu-run --timeout 120`, at load about 27 (heavy):
- `--headless --frames 120 --shot shot.ppm`: `0.940 ms a frame` (claimed 0.913), `most lights offered to one tile 158 (cap 256), tiles over the cap 0`, and it wrote the four PPMs. Exit 0.
- A second run printed 1.900 ms. The figure moves with load.

The pictures: the final frame shows a checkered floor, cubes and spheres washed in many coloured light pools, a sky gradient and no tile seams. The normal view shows a green floor and purple cube fronts, as expected for view-space normals.

## 2. Claims vs reality
Everything checked holds, including the std inconsistency it reports: `Format::is_storable` lists Rgba16Float (std/gpu/types.vl:101-104) while the WGSL translator refuses it.
- The README calls 0.913 ms "the GPU's time". The ANALYSIS correctly narrows it to throughput.
- The windowed summary prints `1280 x 720` from constants (main.vl:191) while it rendered 2560x1440. The README notes the real size.
- The test "every light in front of the camera" samples one time, t = 1.5 (scene.vl:364).
- The "not verified" list is candid: keys, a brute-force culling reference, and on-screen output.

## 3. Task coverage
- Generated scene (floor, cubes, spheres): done.
- G-buffer into several targets (albedo, normal, linear depth) in one MRT pass with a hardware depth test: done.
- ≥256 moving coloured point lights: done (512).
- Light culling in a compute pass (16×16 tiles): done.
- Lighting pass (compute, into HDR): done.
- Tone mapping (ACES and gamma): done.
- Keys toggle G-buffer views: done in code, untested.
- Headless writes each G-buffer view and the final frame, and prints the frame time: done.

## 4. Correctness of the core
- G-buffer: normals go through the rigid view matrix, and depth is −z_view into R32Float (clear 0 = sky). Correct.
- Cull (shaders.vl:47-76): the projected centre and a radius scaled at depth d − r, tested as a circle against the tile rectangle, with an `atomicAdd` slot and a cap. Two approximations:
  - Off-axis, a sphere projects to an ellipse larger than this circle (about 1/cos²θ). Near the screen edges the test is not strictly conservative.
  - Lights with d ≤ r are dropped (line 61), although a light straddling the camera plane can still light visible pixels. This camera never produces that case.
- Light pass: it reconstructs view position from linear depth and `proj[0]`/`proj[5]` correctly. Workgroup = tile, so the tile index matches the cull's. The attenuation is windowed and correct.
- Synchronisation: write_buffer is ordered before the next submit (std's contract), and the passes are separate. Fine.
- `perspective` (scene.vl:272-278) is OpenGL-style (z in −1..1) on Metal (0..1). It works, but the effective near plane becomes 2fn/(f+n) ≈ 0.2 and half the depth range is wasted. Harmless here; terrain got this right.
- Checks: tile stats are plausibility numbers only. The headless run fails only on errors; there is no NaN or brightness check.

## 5. Code quality
A clean four-module split. The `Renderer` encapsulates the GPU state well, and `source([FRAME, X])` shares the uniform declaration across modules nicely. Ownership is used correctly (sink `Device`/`Queue`, inout encoders). Smaller points:
- `hue_channel` clamps by hand (scene.vl:203-208); `.clamp(0.0, 1.0)` exists.
- It defines its own f32 `PI` (scene.vl:6) instead of using std's.
- A 37-field struct, acceptable for this size.
- The window ignores resizes (stated).

## 6. Borrowing
- `kernel()`/`source()` (render.vl:22-34) are fluid2d's `kernel`, split in two.
- `shot` (render.vl:233-252) is fluid2d's `snapshot_in`.
- The window loop shape and `secs` also come from fluid2d.
- The renderer, culling and shading are original.

## 6b. New features
It used MRT exactly as intended: `PassDesc::color(av).with_color(nv).with_color(dlv).with_depth(dhv)` with `desc.target(...)` (render.vl:117-120, 193-194), one pass where round 1 needed three. Depth-only passes are not applicable. `map_read_copy_in` was not needed (tile_stats reads the view in place). It uses std math (`tan`, `sin`, `cos`, `sqrt`, `floor`).

## 6c. Compiler bug
Not hit. Every shader is `let`-bound (render.vl:32, 116, 129).

## 7. Tests
Five tests: RNG range, mesh counts, look-at centre projection, lights in front of the camera, colour range. The last is true by construction, because `hue_channel` clamps. Missing: a CPU mirror of the tile test against brute force (the obvious check, and admitted), the uniform layout, and the depth convention.

## 8. Verdict
A complete, correct-looking deferred renderer with real tiled culling and an MRT G-buffer at about 1 ms/frame, plus a genuine std inconsistency reported with a repro. The checks are plausibility numbers rather than tests that can fail. The culling approximation and the GL depth convention are small blemishes. The report is thorough and honest.

**Grades:** result **A**, code **A-**, honesty **A**.
