> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: terrain

## 1. Reproduce
`volec main.vl -o terrain`: ok. `volec test main.vl`: `8 passed (8 #[test]; -O0 and -O2 agree)`. Through `gpu-run --timeout 120`:
- `./terrain --headless --shot c1.ppm --camera 1`, exit 0. Output identical to `run-camera1.txt`: heights min -55.8, max 88.2, mean 3.8, 44.3 % under the sea; camera 0 steps 24/45/104/83 and 109376 of 589824 triangles; shadow map 38.3 %; all checks ok.
- `--seed 7 --camera 0` and `--camera 2` also pass.
- The pictures are convincing: grass, beaches, rock on slopes, snow caps, cast shadows, a fresnel sea and fog.

## 2. Claims vs reality
- Every number reproduces.
- "Sampled with a 3 x 3 comparison" is a manual `textureLoad` compare (shaders.vl:121-136), not a comparison sampler. It is fine, the wording is just loose.
- What it does not mention: the fly-over leaves the terrain (section 4). It never watched the window, which it says.
- No overstatement of timings: it explicitly declines to report one.

## 3. Task coverage
- Fractal noise heightmap computed on the GPU: done (7-octave value noise in a compute kernel).
- Mesh with distance-based LOD: done (16x16 chunks at step 1/2/4/8, skirts against cracks, vertex-pulled from the height buffer).
- Sun shadow map from a depth-only pass: done (2048², 3x3 PCF).
- Fog; materials by height and slope (sand, grass, rock, snow): done.
- Water at sea level: done (an opaque plane).
- Headless fixed-camera shots and checks (noise range, triangles per LOD): done, one camera per run.
- Fly-over: partial. It flies off the map after about 22 s (below).

## 4. Correctness of the core
**Correct parts.**
- Noise (shaders.vl:14-52): an integer hash, smoothstep value noise, and normalised fBm. Coordinates stay positive, so `vec2<u32>(floor(p))` is safe.
- Vertex generation (`corner`, :75-94): it decodes quad and corner from `vertex_index` and the chunk from `instance_index`, then hangs four 40-unit skirts. The CPU (`chunk_verts`) and GPU agree on the counts.
- Normals by central differences; the slope and height material blend is sensible.
- The shadow matrices are correct (the tests cover ortho and look_at). The normal offset of 1.5 plus a bias of 0.002 fights acne.
- The shadow pass uses the camera's LOD for the sun's geometry. That is acceptable, and the normal offset hides the mismatch.

**Bug in the windowed fly-over** (main.vl:48-52): `eye.x = -500 + 45 t`, and `t` grows without bound (:214). The terrain spans x ∈ [-512, 512], so after about 23 s the camera is over open sea. After about 55 s it passes the sea plane's ±2000 edge (:157) into sky. The path never loops.

**Weak checks.**
- The LOD "check" (main.vl:125) fails only if every chunk is at step 1. The triangle counts are computed on the CPU from the same `steps`, so they are self-consistent by construction, not measured.
- The shadow-coverage check (main.vl:133-144) reads back the real depth texture. That is a genuine GPU check.

## 5. Code quality
- A clear split: mat, terrain/LOD, shaders, scene/GPU, main. Short functions and good comments.
- `Scene::new_in` takes `sink` handles. The WGSL constants are mirrored from vole, and that is documented.
- Small items:
  - The variable `first` is dead (main.vl:207, :262).
  - The NaN test is `h != h` (main.vl:94) where `is_nan` exists.
  - `np.cell` is uploaded but unused (shaders.vl:11).
  - `steps[c as usize]` is a no-op cast.
- No `unsafe`.

## 6. Borrowing
- `write_ppm` and `verdict` follow fluid2d.
- The vertex-pulled chunked terrain, the noise and the shadowing are its own design; none of it is in the examples.

## 6b. New in 0.25.2.2
- The best use this round: **one WGSL module (SCENE) serves three pipelines**: the depth-only `vs_shadow`, terrain `vs/fs`, and sea `vw/fw` (scene.vl:57-72).
  - The water bind group binds only binding 0 (:72).
  - The shadow group binds 0–2 without the texture (:59-60).
  - Both rely on a pipeline's layout now being the bindings its own entry points use.
- The noise uniform is made with `buffer_init` (:46), so `gpu.unwritten` never comes up.
- No new storage formats, integer methods or `adapter.limits()`.

## 6c. Mapped view across a submit
`hs = s.read_heights()` (main.vl:86, a `map_read` view) stays in scope while later submits run (main.vl:139, :157). Those passes only read `heights`, though; nothing writes it after the noise. The results do not depend on the bug.

## 7. Tests
- Eight CPU tests: matrices, LOD thresholds, triangle formulas, chunk centres.
- The headless run checks the noise range, sea fraction, NaNs and shadow coverage on real GPU data.
- Missing:
  - any crack or seam test (a coarse/fine neighbour pair rendered and compared);
  - any image sanity check;
  - a check that the fly path stays over the terrain.

## 8. Verdict
The prettiest and most self-contained scene of the round, with all features present, real GPU-side checks for noise and shadows, and a smart use of one shader module for three pipelines. The windowed fly-over flies off the map within half a minute, and the LOD check is close to a tautology. The report is accurate and modest.

**Grades:** result **B+**, code **A-**, honesty **A-**.
