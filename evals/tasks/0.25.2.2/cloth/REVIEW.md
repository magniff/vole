> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: cloth (PBD cloth)

## 1. Reproduce
Built in a scratch copy: ok. `volec test main.vl` → 5 passed.
- `gpu-run --timeout 120 -- ./cloth --headless --steps 600 --shot shot.ppm`, exit 0. Identical to `headless-run.txt`: rms 0.0616 → 0.0149, largest 0.0800 → 0.2753, total energy 47001.7 at frame 120 and never above, NaN 0, 0.955 ms a frame.
- `--steps 300 --grab`: `0.0039 away at frame 240: ok`.
- `--steps 300 --gravity 0 --no-sphere`: rms 0.0009, largest 0.0056. The solver itself converges.
- `--size 16 --grab`: panics, `cloth.vl:77:8: index out of bounds: index 2176, length 1024`.
- The shot shows the sheet hanging from its two corners, draped over the hidden sphere and pooling on a checked floor. It is lit and two-sided.

## 2. Claims vs reality
The numbers hold. The report is candid that the largest error is about 0.28 (28% stretch at rest near the pins) and that energy rises about 10% at impact. One framing issue: "constraint error falls 0.062 → 0.015: ok" relies on the sheet being *deliberately* started 8% stretched (`main.vl:42`, `cloth::initial`). The README and a code comment say so, but the ANALYSIS headline does not, and the largest error *grows* 3.5×.

## 3. Task coverage
- At least 64×64: done.
- Stretch and bend distance constraints, graph colouring: done (12 classes).
- Gravity: done.
- Wind: done (window key only; headless runs wind 0).
- Sphere and floor collision: done.
- Pinned corners: done.
- Grab-and-drag: done, scripted headless; the mouse path is unverified.
- Lit two-sided mesh: done.
- GPU normals: done.
- Checks (error, energy, NaN) and shots: done.

## 4. Correctness of the core
- **Colouring**: correct. Stretch classes are mod 2 and bend classes mod 4 along each axis, so no particle is in two constraints of one class (`shaders.vl:90-117`). The PBD projection is split by inverse mass, with collision after each sweep and velocity from positions (`UPDATE`).
- **Normals** use central differences, and the shading flips toward the eye.
- **Projection and depth** are correct.
- **Bug**: the headless grab target `gi = 32*n + 32` (`main.vl:65`) assumes n ≥ 33 (reproduced above).
- **Stale size**: in the window, `sz` is captured once (`main.vl:219`), so `ray`/`pick` use stale dimensions after a resize while the surface and depth are resized.
- **Performance**: every dispatch is its own compute pass (`sim.vl:107-114`), which is 4 × (1 + 16·13 + 1) + 1 = 841 passes a frame. Dispatches in one pass are ordered (guide gpu#atomics, a sentence the agent could not find under that heading). It still runs at about 1 ms a frame.
- **Checks**: the energy check (≤ 1.02 × frame 120 after landing) is a no-blow-up check on a heavily damped system (0.99 per substep). NaN counting is fine. The 28% stretch at rest means the cloth is visibly elastic at 16 sweeps; the report quantifies this (0.47, 0.28, 0.17 for 8, 16, 32 sweeps).

## 5. Code quality
The split is clear (cloth.vl CPU, sim.vl GPU, shaders.vl), with good comments. There is no `unsafe`. Dead bits: `Input.down` is set but never read, and `let _ = t;` (`main.vl:310`). `not_finite` uses `x - x != 0.0` (`cloth.vl:193`); `f32::is_finite` exists. The small `V3` type is reasonable. There are 12 one-vec4 uniform buffers for the classes (`sim.vl:218-224`); dynamic offsets or a storage buffer would do. `dispatch1` hides the pass-per-dispatch cost.

## 6. Borrowing
The `kernel()` helper is from the guide, and `snapshot_in` is fluid2d's with a depth texture added. The window loop follows fluid2d. These are adapted patterns.

## 6b. New in 0.25.2.2
It uses one module per kernel, with no shared-module use, storage formats, integer methods or `adapter.limits()`. The `n·n/64` groups are tiny anyway. `gpu.unwritten` did not fire, because `set_frame` precedes every step.

## 6c. Mapped views
`Sim::read` (`sim.vl:318-335`) maps `stage_x` and `stage_v` after one submit and copies them out; the views die in the function. No dependency.

## 7. Tests
There are 5 unit tests: the camera ray, zero and stretched constraint error, pick, and NaN counting. They are good targeted CPU tests. Headless covers the solver, collisions and the scripted grab. Missing: wind, the mouse path, sizes below 33 with `--grab`, and an honest constraint test from rest (the `--gravity 0` run exists but is not part of the verdicts).

## 8. Verdict
This is a working, good-looking GPU PBD cloth with correct graph colouring and GPU normals. Most of the 19 minutes went to physics, not vole. Deductions: a stretchy result (28% at rest), a constraint-error verdict made to pass by the initial stretch, a hard-coded grab index, and 841 compute passes a frame from an unanswered ordering question. The report is otherwise thorough and honest.

**Grades:** result **B+**, code **B**, honesty **A-**.
