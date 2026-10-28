> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: terrain

## 1. Reproduce
- Build ok, check 0 errors, `volec test main.vl`: 5 passed.
- `gpu-run --timeout 60 -- ./terrain --headless --camera N --shot $S/trN.ppm` for N = 0, 1, 2, all exit 0:
  - `noise: 66049 heights, min 0.149, max 0.835, mean 0.490 … ok`
  - LOD counts: camera 0 has 19 tiles at LOD2 and 45 at LOD3 (6528 triangles); camera 1 has 15/18/30/1 (51904); camera 2 has 11/16/34/3.
  - `shadows: 16564 of 262144 pixels (6.32%) … ok`, identical for every camera because it always uses the overview camera.
- The overview shot shows sea, sand, grass, rock, snow, fog and faint cast shadows. Cameras 1 and 2 are plausible, if flat-looking.
- The window was not run.

## 2. Claims vs reality
Every number in the README and ANALYSIS reproduces exactly. The windowed failure is stated plainly, and the agent owns up to its own `clone()`-in-a-loop bug.

Errors:
- **"WGSL in strings is compiled at build time" (§5) is wrong.** `dev.shader_wgsl` compiles at run time.
- **The README has the snow rule backwards.** It says "snow above about 24 units on steep faces"; the code puts snow on *gentle* slopes (`smoothstep(0.7, 0.85, n.y)`, `shaders.vl:132`).
- **The printout double-counts skirts.** It says `drawn: … triangles (+ 2 water, + the skirts)`, but `tris_per_tile` (`mesh.vl:42-45`) already includes them.

## 3. Task coverage
- Fractal noise heightmap on the GPU: **done** (6-octave value noise in a compute shader).
- Mesh with distance-based LOD: **done** (8×8 tiles, 4 levels, skirts).
- Sun shadow map from a depth-only pass: **done**. It needs a dummy R8 color target because `PassDesc` requires a color attachment (a genuine std gap); filtered with 3×3 PCF.
- Fog: **done** (exponential).
- Materials by height and slope (grass, rock, snow): **done**, plus sand.
- Water at sea level: **done** (blended quad with a Blinn glint).
- Headless shots and checks: **done**.
- Fly-over: **done**, but each segment is eased with smoothstep (`main.vl:217`), so the camera stops at every waypoint.

## 4. Correctness of the core
- **Matrices are correct.** `look_at`, perspective and ortho are correct right-handed [0,1] forms (`mat.vl:45-71`). The shadow UV flips y correctly for Metal (`shaders.vl:115`), and the 0.002 depth bias is reasonable.
- **Normals and draw order are correct.** Central-difference normals scaled by SCALE are right (`:73-77`). The water is drawn after the terrain with depth test on and depth write off.
- **One bug: the aspect ratio ignores resizes.** The windowed aspect uses the initial `px` even after a resize (`main.vl:404`).
- Cosmetic: the `(v as f64) as f32` round trips (`main.vl:233-238`) do nothing.

Checks:
- **The noise check is weak.** fbm normalised by the sum of amplitudes lies in [0,1] by construction; only "spread > 0.3" says anything.
- **The LOD check is CPU arithmetic** on the CPU-chosen levels, not what the GPU drew.
- **The shadow on/off difference is meaningful** but would also pass with shadow acne.

## 5. Code quality
- Reasonable split: `mat`, `mesh`, `shaders`, and a large `main.vl` holding the GPU setup and render.
- `setup(dev: sink, queue: sink, mesh: sink)` is idiomatic; handles are copied into locals before the pass closures.
- Hand-rolled Newton `sqrt_f`; no trig (waypoints instead), as expected.
- Allocates a `Vec` for the uniforms and one for the spans every frame (fine at this size). No `unsafe`.

## 6. Borrowing
- The window loop and readback follow the guide and fluid2d's shape.
- No large verbatim blocks.
- The index-buffer LOD scheme and the vertex shader that reads the height buffer are original.

## 7. Tests
- **The five tests:** sqrt, look_at, ortho, exact index counts per LOD (good: it checks 2q²+8q against the real buffer), LOD thresholds.
- **Missing:** perspective, the fly path, any check of the shadow-map coordinates. The headless checks are mostly existence checks.

## 8. Verdict
Every feature on the list is present and correct in its maths. The pictures are acceptable rather than striking, and the windowed path is unverified. The report is accurate on numbers, with one wrong claim about compile time and a README wording slip.

**Grades:** result **B**, code **B**, honesty **B+**.
