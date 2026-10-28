> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: sph (2D SPH, 102,400 particles)

## 1. Reproduce
`volec main.vl -o sph` printed `ok: built sph`. `volec test main.vl` gave `8 passed (-O0 and -O2 agree)`.

`gpu-run --timeout 120 -- ./sph --headless --frames 120 --shot shot.ppm` (load 9.8) exited 0:
```
sort at the start (counts, prefix sum, order vs CPU): 0 wrong
prefix sum of 100003 counts vs CPU: 0 wrong
frame 120: mean density 1032.5 (3.25% of rest)
120 frames: 42.67 ms a frame (67 substeps each)
sort after the run (wrong entries): 0
density settling: the last 30 frames moved it 0.279% of rest
particles outside the box or not finite: 0
checks: sort ok, prefix sum ok, escapes ok, density ok
```
The shot shows the tilted box, a free surface with fast (yellow) particles, and a vortex left by the scripted stir.

## 2. Claims vs reality
The numbers match: density 3.20% claimed vs 3.25% measured, and 39 ms vs 42.7 ms per frame under higher load. Points to correct:
- "shot.png shows ... the fluid pooled to one side" is generous. The lattice is 256 rows × 0.005 m = 1.28 m of a 1.4 m tank (cpu.vl:8-13), so the tank is about 91% full and there is little room to pool or slosh.
- "No GPU timer query in the std API I could see": guide gpu has a "Timing GPU work" section, so this is a missed doc, not dishonesty.
- Limits are stated plainly: about 3% above rest, below real time at 60 Hz, window not watched.

## 3. Task coverage
- At least 100k particles: done (102,400).
- Box tilt (arrows) and mouse stir: done, but untested in a window. The headless run scripts both tilt and stir, which is a good touch.
- GPU grid: counting sort with an atomic histogram, a prefix sum and a scatter: done.
- Density, pressure, viscosity and integration: done.
- Particles coloured by speed: done.
- Headless sort and scan vs CPU, density settling, no escapes, shot: done.

## 4. Correctness of the core
- The 2D kernel constants are right: poly6 4/(πh^8), spiky gradient 30/(πh^5), viscosity 40/(πh^5) (sim.vl:132-134).
- The symmetric pressure term and its sign are correct (shaders.vl:149, 171). Pressure is clamped at ≥0 (no tension), and the README says so.
- Viscosity omits the 1/ρ_i factor (shaders.vl:172, 177). This is absorbed into MU, but it is not textbook.
- The single-workgroup Hillis–Steele scan (60-90) has its barriers right, and the 100,003-element test exercises the carry between tiles.
- The escape check is mostly structural, because integrate clamps every position into the box (200-203). It can only catch NaNs.
- The density check (main.vl:98-100: within 5% of rest, settling under 1%) is reasonable but loose.

## 5. Code quality
The layout is clean: constants and CPU checks in cpu.vl, GPU in sim.vl, WGSL in shaders.vl, CLI in main.vl. Names are good and there is no `unsafe`. std float math is used (`sin`, `cos`, `clamp`, `ceil`). Issues:
- The substep dispatch sequence is duplicated between `step` and `sort_only` (sim.vl:243-254 vs 273-279).
- `secs()` is a trivial wrapper (main.vl:25-27).
- `check_sort` returning `(count, first message)` is a nice design.

## 6. Borrowing
These come from fluid2d sim.vl:161-179 and 405-424, near-verbatim:
- `kernel()`, `storage()` and a 1D variant of `run()` (sim.vl:75-93);
- `snapshot_in` (sim.vl:337-357).

The ANALYSIS says it followed fluid2d. The physics and the sort are original.

## 6b. New features
None of them apply (single render target, no depth). Readbacks use `map_read` views correctly.

## 6c. Compiler bug
Not hit: the shader is bound to a `let` (sim.vl:80).

## 7. Tests
8 CPU tests cover the lattice, mass, grid size, gravity under tilt, the window-to-box mapping, fitting the box, the exclusive scan, and `check_sort` accepting a correct sort and rejecting a wrong one. Testing the checker itself is a good habit. Not tested:
- the force kernels against a CPU SPH step on a few particles;
- the windowed mouse mapping beyond the centre point.

## 8. Verdict
A working 100k-particle GPU SPH with a genuinely verified counting sort and scan, and the mouse and tilt scripted into the headless run. The simulation is plausible but the tank is too full to look like much, and the escape check proves little. The code is tidy. The report is accurate, with slightly generous picture descriptions.

**Grades:** result **A-**, code **A-**, honesty **A-**.
