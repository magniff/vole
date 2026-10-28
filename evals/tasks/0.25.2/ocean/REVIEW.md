> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: ocean (Tessendorf FFT ocean)

## 1. Reproduction
All builds and runs are in the orchestrator's scratch folder (`scratchpad/review/ocean/`), from a copy of the sources. Nothing was written to the project folder.
- `volec main.vl -o …/review/ocean/ocean`: `ok: built` (2.0 s).
- `volec test main.vl`: `4 passed (4 #[test]; -O0 and -O2 agree)`.
- `gpu-run --timeout 120 -- ./ocean --headless --shot …/shot.ppm` (waited 20.7 s, load 26.3), exit 0:
  - `fft: 16 x 16 … largest error 5.86e-6 (1.71e-7 of 34.2): ok`
  - `fft: 32 x 32 … 1.79e-5 (2.29e-7 of 78.0): ok`
  - `height: 256 x 256 cells, 60 frames (1.97 s): mean 1.11e-10, rms 0.4846 m, skew 0.023, range -1.487 .. 1.686 m`
  - `Parseval … = 1.000000: ok`
  - `spectral sum at 16 points, worst |GPU - CPU| = 2.13e-7 m: ok`

These match the README digit for digit. The 640x360 shot is a convincing ocean: a sky gradient, a sun disc, dark Fresnel-lit water, a sun glint and a hazy horizon that hides the patch edge. I did not run the windowed mode.

## 2. Claims vs reality
- Every headless number and the test count reproduce.
- **Mild overstatement.** ANALYSIS and README say the 16-point check "covers evolve and both FFT passes" at 256. It reads only the height lane (`a0.x`, main.vl:229).
  - The displacement spectra (`-i k/|k| H`, shaders.vl:100-105) are never checked against a CPU formula at 256.
  - Neither is the whole `b0/b1` chain.
  - The FFT kernel itself is checked on all 4 lanes, on 16x16 and 32x32 grids.
- **Candid about limits:** the interactive keys were never driven, and `--wind` is ignored in headless.
- **Not re-checked:**
  - the windowed timing of 8.5 ms per frame;
  - the story that `fix --suggested` turned a float `abs` into an i64 one. It is plausible and well described.

## 3. Task coverage
- Phillips spectrum with Gaussian random phases (GPU `init`, shaders.vl:46-73): done.
- Time evolution: done.
- Inverse FFT every frame, in compute passes with ping-pong buffers: done (ocean.vl:229-253).
- Height and normals: done. Normals come from finite differences of displaced neighbours, which is acceptable.
- Displaced, lit, depth-tested mesh: done.
- Sky reflection with Fresnel, sun highlight: done.
- Foam: partial. It is a Jacobian threshold with no persistence, and probably sits in the wrong place (§4).
- Movable camera: done, but untested.
- Headless FFT vs CPU DFT, height statistics, shot: done.
- README, tests: done.

## 4. Correctness
- **FFT** (shaders.vl:131-157): bit-reversed load, radix-2 decimation in time, twiddle `e^{+2πij/m}`, unnormalised. Every barrier is in uniform control flow. Correct.
- **Evolve** (shaders.vl:87-93): correct mirror index and H(k,t).
- **Probable sign bug in the choppiness.**
  - Setup: `D = -i k̂ H` with `lambda = +1.0` (ocean.vl:102).
  - Why: for `h = cos kx` this gives `D = +sin kx`, so `x' = x + λ sin kx`.
  - Effect: crests stretch and troughs compress. Sharp crests in this form need λ < 0.
  - Consequence: the Jacobian foam (shaders.vl:202-203) lands in the troughs, not on the crests.
  - No check would catch it.
- **Mesh and Jacobian** (shaders.vl:181-205): correct periodic wrap and Jacobian; the normal `cross(tz, tx)` points up.
- **Projection** (cpu.vl:127-136): a correct right-handed projection to depth 0..1. The sky ray reconstruction (shaders.vl:247) is consistent with it.
- **Synchronisation:** evolve plus four FFT dispatches share one compute pass (ocean.vl:239-252). This relies on std::gpu running dispatches in order. The 256-cell point check confirms it does here.
- **Buffer usages:** every storage buffer gets `MAP_READ|COPY_DST` (ocean.vl:76). Wasteful but harmless.
- **Numerics:** `AMP` is tuned by hand (main.vl:30). The `exp(-k²·1e-6)` small-wave damping does nothing at 1 m cells.

## 5. Code quality
- **Structure:** a clean split into cpu / ocean / shaders / main, a shared `COMMON` WGSL prefix, good comments.
- **Duplication:**
  - The CPU H(k,t) is written twice (main.vl:91-102 and 205-217).
  - The cos/sin tables are built twice (cpu.vl:64-70, main.vl:81-87).
- **Dead code:**
  - `start` (main.vl:341) is unused.
  - `seed` is passed to `set_time` for nothing.
- **Small issues:**
  - `win.request_frame()` runs after every event (main.vl:438) as well as at line 408.
  - Windowed mode makes a second `Instance` (main.vl:320).
  - `inout self` is used on read-only methods (`record_sim`, `record_draw`, `heights`).
- **Errors and `unsafe`:** Result and `?` are used properly. There is no `unsafe`.
- **Hand-rolled math, as expected for 0.25.2:** a Taylor sine (cpu.vl:13-29), a 64-step Newton square root (cpu.vl:36-45), and `abs`.

## 6. Borrowing
Patterns are adapted from examples/gpu/fluid2d:
- `snapshot_in` (ocean.vl:323-346) is nearly verbatim from fluid2d sim.vl:418-437, with a depth texture added.
- The frame-clock and frame-timing loop and `secs()` follow fluid2d main.vl:326-345.
- The CLI builder follows fluid2d's.

The FFT, the physics, the checks and the shading are original.

## 7. Tests
- **The 4 `#[test]`s are weak:**
  - The DFT-of-a-delta test (cpu.vl:181-192) passes for either exponent sign, so it cannot catch a sign error.
  - The projection test checks only the centre point.
  - Nothing tests `pack` against the WGSL `Par` struct, the CPU H(k,t), or the camera axes.
- **The headless checks are strong where they reach:**
  - the GPU FFT against an independent f64 DFT on random data;
  - a point-wise spectral sum on the 256 grid.
- **Two checks add little:**
  - Parseval mostly repeats the point check.
  - The mean check is nearly tautological, since h0 at k = 0 is zero by construction.
- **Not covered:** the Phillips values from `init`, the displacements, the normals, the foam.

## 8. Verdict
This is a working, good-looking FFT ocean. The GPU FFT matches a CPU DFT to about 2e-7 relative error, and the full 256x256 height field is checked point by point. The code is well organised and commented. The weaknesses:
- a likely inverted choppiness sign, which puts the folds and the foam in the troughs;
- the displacement path is never checked;
- some duplication;
- thin unit tests.

The report is accurate and candid, with one mild overstatement of what the 256-cell check covers.

**Grades:** result **A-**, code **B+**, honesty **A-**.
