> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: sph (2D SPH fluid, 102,400 particles)

## 1. Reproduction
- `volec main.vl -o …/scratchpad/review/sph/sph` (from a copy of the sources): `ok: built`, 1.8 s.
- `volec test main.vl`: `4 passed (4 #[test]; -O0 and -O2 agree)`.
- `gpu-run --timeout 120 -- ./sph --headless --shot …/shot.ppm` (waited 11.7 s, load 27.6), exit 0, about 9.5 s of GPU time:
  - `step 8000: mean density 0.9026 x rest over all particles; bulk 0.9810 x rest over the 64% at 90% or more`
  - `sort: … cell ids vs CPU: 0 differ; counts vs CPU histogram: 0 cells differ`
  - `prefix sum (GPU) vs CPU exclusive scan: 0 of 143641 entries differ`
  - `order: 0 … not a permutation, 0 out of cell order; verdict ok`
  - `speed: mean 1.847 m/s, largest 10.902 m/s`
  - `escape: 0 …; verdict ok`, `density: mean 0.9810 …, verdict ok`
- The numbers differ a little from the README's (bulk 0.9872, 71%). The atomic scatter orders particles differently on each run. The checks pass either way. The windowed run was skipped.
- The shot shows a tilted box with a splashing body of fluid and a spray of loose particles. The bottom layer is speckled red and blue: neighbouring particles move at very different speeds, so the fluid is visibly noisy and not settled.

## 2. Claims vs reality
- **What holds:**
  - The sort, scan and order checks are exact (zero differences) and reproduce.
  - The tests pass.
  - The "about 1/12 of real time" limit is stated honestly.
  - Not testing the mouse is admitted.
- **Overstated: "Bulk mean density settles to 0.987".**
  - The all-particle mean falls steadily: 0.99, then 0.94, then 0.90.
  - The share of particles counted as "bulk" falls too: 86%, then 79%, then 64%.
  - At t = 0.64 s the fluid is still sloshing, with a mean speed of 1.85 m/s.
  - Nothing tests settling. The check (`main.vl:222`) looks at one final value of a subset picked by density ≥ 0.9·ρ0 (`main.vl:131`). That subset's mean is at least 0.9 by construction.
- **Small inaccuracies:**
  - The ANALYSIS lists "Newton sqrt" among the math it had to write. It exists only on the CPU side (`main.vl:237`).
  - `shaders.vl:2-3` and `sim.vl:4` say "every kernel has the same bind group layout". `sim.vl:141` contradicts this.
  - `cpu.vl:76` says |x| ≤ 3.2, but `main.vl:163` calls `sin` with arguments up to 2π. This is harmless: the Taylor series is still accurate in f64 there.

## 3. Task coverage
- ≥100k particles: **done** (102,400).
- Tilt the box: **done** (right drag, arrows).
- Stir with the mouse: **done in code**, untested.
- GPU grid counting sort and prefix sum: **done** (`shaders.vl:40-93`).
- Density, pressure, viscosity, integration: **done** (`shaders.vl:96-199`).
- Colour by speed: **done** (`shaders.vl:214-230`).
- Headless check of the sort and scan against the CPU: **done**, strong.
- Mean density settling: **partial**, and the check is weak (§2).
- No particle escaping: **done**, but nearly tautological (§4).
- Shot: **done**.

## 4. Correctness of the core
- **Kernel normalisations are right for 2D:**
  - poly6 4/(πh⁸) (`shaders.vl:104`)
  - spiky gradient 30/(πh⁵) (`:144`)
  - viscosity Laplacian 40/(πh⁵) (`:145`)
- **Pressure and viscosity:**
  - The pressure force has the symmetric form m(pᵢ/ρᵢ² + pⱼ/ρⱼ²)∇W, with the sign right (`:164`).
  - Pressure is clamped at zero (`:131`), so there is no cohesion, which adds to the spray.
  - Viscosity (`:165`) leaves out the 1/ρᵢ factor. VISC absorbs it, and the README calls it a "fixed coefficient".
- **Parameters are consistent:** mass = ρ0·dx² (`cpu.vl:20`), h = 2.4·dx, CFL c·dt/h = 0.30.
- **Scan (`shaders.vl:57-85`):** a correct Hillis–Steele scan in one workgroup over 561 tiles.
  - Barriers sit in uniform control flow.
  - The carry from `tmp[255]` is read between barriers.
  - It is serial over the tiles, but correct.
- **Synchronisation:** all seven dispatches run in one compute pass (`sim.vl:198-206`). This relies on std::gpu ordering the dispatches, as fluid2d also does.
- **Check quality:**
  - The sort check (`main.vl:53-119`) is genuinely strong. It re-sorts the current positions and compares cell ids, the histogram, the scan, the permutation and the ordering.
  - The escape check (`main.vl:212-220`) can only fail on NaN, because `K_INTEGRATE` clamps every particle into the box (`shaders.vl:191-194`). Its `!(…)` form does catch NaN.

## 5. Code quality
- **Structure:** a clean four-file split, with good names and comments:
  - `cpu.vl`: constants and CPU references
  - `shaders.vl`: WGSL parts
  - `sim.vl`: the GPU object
  - `main.vl`: CLI and loop
- **Idiomatic vole:** `inout self`, `&enc`, `Result` with `?` in `Sim::new_in`, `gpa` passed down, `std::cli`. No `unsafe`.
- **Duplication:**
  - `Sim::sort` repeats the first four dispatches of `Sim::step` (`sim.vl:184-207`).
  - The speed loop runs twice (`main.vl:182-203`).
  - `sqrt_f64` always runs 64 Newton iterations.
- **Hand-rolled math, as expected for 0.25.2:** `floor_f32`, Taylor `sin`/`cos` (`cpu.vl:36-97`) and a Newton sqrt.
- **Minor fragility:** `snapshot_in` assumes w·4 is a multiple of 256 (stated at `sim.vl:219`).

## 6. Borrowing
- **Adapted from fluid2d:**
  - `kernel` / `storage` / `run` (`sim.vl:75-93`) nearly match fluid2d `sim.vl:161-179`.
  - `snapshot_in` is fluid2d's without the row stride.
- **Copied verbatim from fluid2d:** `verdict`, `secs` and `floor_f32` (fluid2d `main.vl:48-61,143`).
- **Original work:** everything SPH, the sort and scan, and the checks.

## 7. Tests
- **The 4 `#[test]`s cover:** the CPU exclusive scan, clamping in `cell_of`, the lattice being inside the box, and sin/cos.
- **Missing tests:**
  - none for `to_world` or the wall rotation (a round trip);
  - none checking the CPU `cell_of` against the WGSL, beyond the runtime check.
- **The headless run** covers the sort and scan strongly. It does not cover:
  - density convergence over time;
  - momentum or energy;
  - the stir path;
  - a multi-workgroup scan (there is no such path).

## 8. Verdict
This is a solid, honest first program. The core requirement is fully met and checked exactly against the CPU: a GPU counting sort by cell with a prefix sum, then SPH density, forces and integration for 102k particles. The physics is correctly derived. The visual result is a noisy, splashy fluid rather than a calm one. The "settling" claim rests on a self-selected subset at one point in time, and the escape check is close to tautological. The ANALYSIS is detailed and mostly accurate, with small overstatements.

**Grades:** result **B**, code **B+**, honesty **B+**.
