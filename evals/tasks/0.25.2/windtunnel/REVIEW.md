> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator, who reproduced the key finding: the agent's unmodified program, rebuilt and run with `--headless --steps 30000`, prints `shedding St = 0.207 from 19 upward crossings, probe amplitude 0.0530: in the expected range`.

# Review: windtunnel

## 1. Reproduce
`$S` = the orchestrator's scratch folder, `scratchpad/review`.
- `volec main.vl -o $S/windtunnel`: `ok: built`. `volec check`: 0 errors. `volec test main.vl`: `4 passed (-O0 and -O2 agree)`.
- `gpu-run --timeout 120 -- ./windtunnel --headless --shot …` (load 34, about 2.6 s):
  - `closed box … 1500 steps: mass 9.600000e4, largest drift 1.97e-5 (relative) ok`
  - `closed box: largest |u| 0.03777`
  - `channel, Re 100 … 12000 steps: shedding St = 0.548 from 18 upward crossings, probe amplitude 0.0038: NOT in 0.12..0.22`
  - `largest |u| 0.1423 … finite: true ok`, exit 0
- `--re 30` and `--re 140`: the closed box ends at |u| 0.0256 and 0.0400, so the Reynolds number does reach the collision.
- No window was opened.

## 2. Claims vs reality
Every reported number reproduces almost exactly: drift 2e-5, St 0.55 with 18 crossings and amplitude 0.004, speed 0.142. The report says plainly that shedding was not reproduced, and the README does not gate on it. Those are the honest parts.

Two claims cannot be checked from the shipped binary:
- "Re 240 decays to 0.037": `clamp_re` caps `--re` at 140, so this needed a modified build. The report does say "cylinder-free build".
- The empty-channel Poiseuille number: there is no option for it.

Small errors:
- The comment at `main.vl:36` says the probe is "2 radii behind" the rear. It is 10 cells, one radius (rear at x = 110, probe at x = 120). The README's "10 cells" is right.
- The report attributes the failure to an "under-resolved BGK setup (D=20 cells)". That is the wrong suspect (section 4).

## 3. Task coverage
- D2Q9 BGK on the GPU: **done**.
- Inflow from the left (Zou-He inlet and outlet): **done**.
- Draw and erase obstacles with the mouse: **done** in code (STROKE kernel), not checked live.
- Speed, vorticity and dye views on keys: **done**.
- Reynolds-number control: **done** (`[` `]`, 30 to 140).
- Stable at defaults: **done**.
- Mass-conservation check: **done** (closed box only).
- A known result (vortex shedding): **missing as shipped** (fails, not gated). It is easy to reproduce (section 4).
- Shots: **done**.

## 4. Correctness of the core
I read the kernels against the textbook formulas.
- **Lattice and collision are correct.** The velocity, opposite-direction and weight tables are right (`shaders.vl:22-45`; `opp` maps 1↔3, 2↔4, 5↔7, 6↔8). BGK collision is right (`:117-141`).
- **Streaming and walls are correct.** Pull streaming with halfway bounce-back at solids and at the closed box's edges is right (`:163-176`).
- **Open boundaries are correct.** The Zou-He velocity inlet (`:177-183`) and density outlet (`:184-189`) match Zou and He's equations term for term.
- **Buffer swapping is consistent.** The ping-pong parity in `sim.vl:256-274` uses each buffer in the right order (collide f0 → stream to f1 → fields from f1, then the reverse).

**Why there is no shedding: the setup is exactly mirror-symmetric, not a bug.**
- The walls are rows j = 0 and j = 239 (`shaders.vl:62`), so the fluid's centreline is y = 120.0 in cell-centre coordinates.
- The cylinder's centre is `CYL_Y = 120.0` (`main.vl:32`), tested as `(j + 0.5 - cyl_y)²` (`shaders.vl:65`).
- The initial flow and the inlet are uniform (`:70-79`).
- So the only thing that can break the symmetry is float rounding. The steady symmetric wake (`shot_speed.png`) is an unstable equilibrium, and growth from about 1e-7 takes tens of thousands of steps.
- 12000 steps, analysed after step 4800, sees only the transient and acoustic noise (amplitude 0.004 = 4% of U).

Evidence:
- The **unmodified binary** with `--steps 30000` prints `St = 0.207 from 19 upward crossings, probe amplitude 0.0530: in the expected range`.
- A scratch copy with `CYL_Y = 122` gives St 0.186, amplitude 0.061 at 30000 steps. Its vorticity shot shows a clean Kármán street.
- St around 0.19 to 0.21 is plausible for 8.4% blockage with U taken as the mean inflow.

**Fix:** offset the cylinder by a cell or two, or apply a transverse kick for a few hundred steps, and run 25000 to 30000 steps. The `amp > 1e-4` threshold (`main.vl:137`) is too low to tell shedding from noise; use about 0.01.

## 5. Code quality
- The four-module split (main, sim, shaders, physics) is clean. `inout self`, `sink` and `Result` are used correctly. Helper names are good. No `unsafe`.
- The `HEAD + FUNCS + kernel` shader assembly is neat.
- The D2Q9 tables are written twice, in WGSL and in `physics.vl`. The tests check only the CPU copy.
- Newton `sqrt` (`sim.vl:377`) and Taylor `sin_turns` are hand-rolled, as expected in 0.25.2.
- Minor: a second `gpu::Instance` just for the surface (`main.vl:231`).

## 6. Borrowing
`sim.vl` is fluid2d's `sim.vl` reshaped:
- `kernel`, `storage`, `run`, `sqrt` and `snapshot_in` are copied nearly verbatim (fluid2d `sim.vl:161-203` and `418-438`). `Stroke` follows `Splat`.
- `main.vl` reuses fluid2d's `Input`, `verdict`, fps-title and `--frames` timing loop.
- The LBM kernels themselves are original.

## 7. Tests
- **The four `#[test]`s:** CPU lattice isotropy, omega at Re 100, Re clamping, and the Strouhal estimator on a synthetic sine (a good one).
- **Not tested:** the WGSL `opp` and weights, the Zou-He algebra (testable on the CPU), mass in the channel.
- **The headless mass check is meaningful:** a closed box with an edge leak would show.

## 8. Verdict
A correct, well-structured LBM that is stable at defaults. Its only failure is a missing symmetry breaker plus a run too short for the known-result check. The agent's 8 shedding runs varied grid, Re and probe position, but never the symmetry or the run length. The report is exemplary in not overstating.

**Grades:** result **B-**, code **B+**, honesty **A**.
