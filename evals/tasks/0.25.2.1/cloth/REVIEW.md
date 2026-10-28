> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: cloth (PBD cloth on the GPU)

## 1. Reproduce
`volec main.vl -o cloth` printed `ok: built cloth`. `volec test main.vl` gave `7 passed (-O0 and -O2 agree)`. All runs below went through `gpu-run --timeout 120`:
- `./cloth --headless --shot wind.ppm` (load 9.3), about 1.2 s wall, exit 0: `no NaN ... ok`, `stretch ... (rms 1.67%, max 23.00%): ok`.
- `./cloth --solve-test`: error 0.164 → 0.00209 (128 iterations) → 0.00119 (256), `monotone: ok`.
- `./cloth --headless --calm --drag --shot drag.ppm`: `grabbed particle on its target (worst distance 0.00e0 m): ok`, stretch rms 5.27% and max 135.74% (reported, not checked).

The pictures show an orange cloth hanging from two pinned corners next to the sphere, over a checkered floor. In the drag shot the grab point pulls a crease.

## 2. Claims vs reality
The numbers reproduce exactly (the run is deterministic). Overstatements:
- README: "no particle inside the floor or the sphere (after every frame)". It is sampled only every 60th frame (main.vl:121).
- "the back side is blue" in the pictures: none of the three shots (theirs or mine) shows any blue back face, so two-sided shading is unshown.
- "about 530 dispatches a frame": it is 4·(1 + 128·2) + 1 = 1029 (sim.vl:166-177).
- "I copied the shape, not the code": `kernel()` and `snapshot_in` (sim.vl:55-58, 237-258) are fluid2d's with a depth target added.

The energy-gain disclosure and the unverified window are reported honestly.

## 3. Task coverage
- 64×64 grid: done.
- Stretch and bend distance constraints solved by Jacobi with averaging: done.
- Gravity and wind: done.
- Sphere and floor collision: done.
- Pinned corners: done.
- Grab and drag: done. The windowed picking is untested; the headless drag is kinematic.
- Lit two-sided mesh: done in code, unshown in pictures.
- Normals on the GPU: done.
- Headless constraint error falling, energy behaving, no NaN, shots: done.

## 4. Correctness of the core
- The constraint projection with w_i/(w_i+w_j) and stiffness-weighted averaging is correct (shaders.vl:105-117), and collision runs after every iteration.
- Weak checks:
  - The drag check is tautological, because the collide kernel writes the grab target directly (shaders.vl:133).
  - The penetration check is close to tautological, because positions are read right after the projecting collide pass.
- The stretch limit (5% rms, 50% max) is loose. Max error sits at 21-23% even at rest, at the pinned corners.
- `--solve-test` is the genuinely informative check.
- In the window, the substep h changes per frame (main.vl:305) while velocity is (x−prev)/h (shaders.vl:53), so the velocity is rescaled whenever the frame time changes.
- The cloth starts through the sphere (cpu.vl:145-147, 209-224); the report admits it.

## 5. Code quality
The four modules (cpu: camera, picking, packing, stats; sim; shaders; main) are clean, the CPU projection mirrors the shader, and the comments are good. There is no `unsafe`. Issues:
- `non_finite` is `(x - x) != 0.0` (cpu.vl:276-278) instead of std's `is_finite()`.
- `clampf` is hand-rolled (main.vl:60-62) instead of f32's `clamp`.
- `floats_in` (sim.vl:74-81) re-implements `map_read_copy_in`, which the agent even looked up.
- `push_out` (cpu.vl:245-256) is a CPU mirror used only by a test, so the test checks the mirror, not the kernel.
- Pipelines and groups are copied into locals before the closures (sim.vl:155-164) without need.
- Its own V3 is fine, since std has no vec type.

## 6. Borrowing
`kernel()`, `snapshot_in` and the `run` helper come from fluid2d with small changes. The solver, collision, picking and shading are original.

## 6b. New features
Depth uses `RenderDesc.depth` and `with_depth`, as fits. It missed `map_read_copy_in` (see `floats_in`). MRT and depth-only passes are not applicable.

## 6c. Compiler bug
Not hit. Compute shaders go through a `let` (sim.vl:56). The render pipelines take an inline `wgsl(...)?` argument (sim.vl:119, 123) and work, which suggests the bug is specific to `compute_pipeline`.

## 7. Tests
7 CPU tests: camera centre, ray/pixel round trip, drag plane, push-out, sphere motion, pins, picking. These are good for the interaction maths. The GPU kernels are covered only by the headless run and the solve test. Gaps:
- no check that normals face the camera, though the agent hit exactly that bug;
- no conservation or penetration check per frame;
- nothing exercises the back face.

## 8. Verdict
A complete, good-looking PBD cloth with a real convergence test and an honest account of the energy gain at contacts. Several headless checks pass by construction, and a few claims (every-frame checking, blue back faces, dispatch count) are stated more strongly than the code supports. The code is well organised but hand-rolls std features.

**Grades:** result **A-**, code **B+**, honesty **B+**.
