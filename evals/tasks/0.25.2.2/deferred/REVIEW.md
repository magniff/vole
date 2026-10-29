> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: deferred

## 1. Reproduce
`volec main.vl -o deferred`: ok. `volec test main.vl`: `7 passed (7 #[test]; -O0 and -O2 agree)`. Through `gpu-run --timeout 120`, at 960x600:
- `--headless --frames 600 --lights 256 / 512 / 4096`: 0.254 / 0.351 / 1.107 ms a frame (the agent reported 0.264 / 0.372 / 1.215).
- 60 frames: 0.384 ms.
- 1920x1200 with 512 lights: 1.295 ms, so the cost scales with pixels.
- `--views v --shot final.ppm`: all five views written. The final frame shows coloured light pools on the boxes and the checkered floor.

## 2. Claims vs reality
**Timing.** Can the measurement be trusted? Yes, as pipelined throughput.
- Every frame really is submitted: `render_to` (render.vl:232-237) does write_buffer × 2, one encoder with four passes, then `submit`.
- Only the end waits (main.vl:96-100). `wait_idle` waits on the last committed command buffer of a serial Metal queue, so all earlier frames have finished.
- `write_buffer` on a busy buffer goes through an ordered staging copy (std's Metal backend), so each frame sees its own uniforms.
- In a scratch variant that waits after every frame, latency is 0.75 ms (512 lights) and 1.41 ms (4096). So the reported figures are real overlapped-frame throughput, not latency, and they include the CPU light update. The agent's own caution was appropriate.

**Overstatements.**
- "4096 lights: 1.215 ms" hides that the renderer silently drops lights at that count. In a scratch variant that marks tiles at the cap: at 512 lights, 0 of 2280 tiles hit 127 (the busiest about 104). At 4096, **829 of 2280 tiles (66 % of the 1259 lit tiles) are capped**, so the 4096 timing measures a renderer doing truncated work.
- README "the heat view shows it saturating": the heat map saturates at 24 lights (shaders.vl:186), so it cannot show the 127 cap.
- Everything else (formats, passes, tests, sky tiles at 0) holds.

## 3. Task coverage
- Generated meshes (boxes, spheres, floor): done.
- G-buffer into several targets (albedo Rgba8Unorm, normal Rgba16Float, linear depth R32Float, plus a depth buffer): done.
- At least 256 moving coloured lights: done (256–4096).
- Compute light culling, by tile: done (16x16, depth bounds plus four side planes).
- Tone mapping (Reinhard and gamma): done.
- Keys toggle the G-buffer views: done (untested by hand).
- Headless writes each view and the final frame, and prints the frame time: done.

## 4. Correctness of the core
**Culling** (shaders.vl:76-133) is sound.
- Per-tile min/max of linear depth as atomics on the f32 bit patterns (valid for non-negative floats), with barriers placed correctly.
- Inward-normalised side planes from the corner rays, and a sphere-plane test `dot(v, n) ≥ -r`.
- Sky pixels contribute d = 0 (:86), so any tile with sky gets dmin = 0. That is conservative, not wrong.
- The list is capped silently at 127 (:120, :125); see section 2.

**Lighting** (shaders.vl:144-167): view-space position is rebuilt correctly from linear depth and `tanxy`. The light is transformed to view space per pixel per light (:158); doing that once per light in the cull pass would remove most of the matrix work.

**CPU side.**
- `look_at` and `perspective` (math.vl) are correct for 0..1 depth.
- Light motion runs on the CPU every frame (scene.vl:162, called from render.vl:178): 4096 lights are hashed and uploaded each frame, inside the timed loop.

**Headless output.** It prints only the frame time. There is no numeric check of culling, coverage or the views; they were checked by eye only.

## 5. Code quality
- A clean module split: math, scene, shaders, render, main. `Renderer::new_in` takes `sink` device and queue. `Targets` is rebuilt on resize. The per-frame `Vec`s are allocated once and reused. Comments are good.
- Small items:
  - `clamp01` (scene.vl:136) duplicates Float `clamp`.
  - `PI` is defined by hand (math.vl:4); std::math has it.
  - The fill loops at render.vl:129-136 could be `Vec::filled_in`.
  - `draw` copies 17 fields into locals before the closures, a workaround for the ownership rules.
- No `unsafe`, no wildcard imports.

## 6. Borrowing
- `frame_ppm` (main.vl:61-83) is fluid2d's `snapshot_in` loop.
- The COMMON+body shader concatenation (render.vl:65-70) follows fluid2d's `kernel(parts)`.
- The renderer and culling are original.

## 6b. New in 0.25.2.2
- It uses four modules (COMMON plus each pass). One module could serve all four, but the passes reuse binding numbers for different resources, so separate modules are reasonable.
- Rgba16Float is used, but as render targets (normal, HDR), not storage.
- No integer methods needed, no `adapter.limits()`.
- `gpu.unwritten` did not fire: `update` writes the camera before every submit.

## 6c. Mapped view across a submit
None. Each `frame_ppm` maps a fresh buffer, and the view ends with the function.

## 7. Tests
- Seven CPU tests (matrices, mesh sizes, index range, hsv, rnd, light ranges). The perspective test checks only `p[0]`.
- Nothing checks the GPU results. A CPU reference cull of a few tiles, or printing the maximum and capped tile counts, would have exposed the 4096-light truncation.

## 8. Verdict
A complete, well-structured deferred renderer with real tiled culling, and a nice final image. The frame times are genuine (pipelined) and reproduce. However, the headline 4096-light number comes from a configuration that silently drops lights in two-thirds of the lit tiles, and the heat map scale (24) hides this. The headless mode verifies nothing but speed. The report hedges the timing honestly but misses the cap.

**Grades:** result **B+**, code **A-**, honesty **B+**.
