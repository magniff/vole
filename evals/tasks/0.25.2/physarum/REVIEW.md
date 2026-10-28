> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator, who confirmed the gain-key bug in the source (tune.vl:38 gain 0.03; main.vl:164-167 nudges it by ±0.25 within 0.25..8).

# Review: physarum

## 1. Reproduction
All commands were run from the orchestrator's scratch folder (`scratchpad/review/physarum/`). The project folder was not touched.

- `volec main.vl -o …/physarum` → `ok: built` (1.1 s). `volec check` → `ok: 0 errors`.
- `volec test main.vl` (on a copy of the sources) → `3 passed (3 #[test]; -O0 and -O2 agree)`.
- `gpu-run --timeout 120 -- ./physarum --headless --steps 400 --every 100 --shot shot.ppm`:
  - totals 4.598901e7, then 4.600001e7 three times; 0 agents outside;
  - all three verdicts `ok`; `0.66 ms a step`; exit 0;
  - the load was 37, against the agent's 2–3.
- `--headless --check` → three `ok`, exit 0.
- `--agents 4000000 --steps 200` → total 1.840000e8, `1.80 ms a step`.
- `--size 128 --agents 200000 --speed 4 --turn 90` → 9.200003e6, 0 outside, exit 0.
- Extra run: `--turn 0`, where agents never turn, so the trail map has no effect on them. **All three verdicts are still `ok`**, and the image is a uniform diffuse disc, not a network.
- The default shot shows thick, worm-like trail networks inside the central disc. It is a correct-looking Physarum pattern at 400 steps.

## 2. Claims vs reality
- **These hold:**
  - the build and the 3 tests;
  - total = 4.600e7, matching n·D·(1−d)/d;
  - agents stay inside;
  - the 4M-agent run.
- **Timings:** measured 0.66 and 1.80 ms against the claimed 0.53 and 1.40 ms. The gap fits the higher load.
- **Honest:** the agent itself says the "grows" check is weak, and that the windowed mode and keys never ran.
- **Overstated:**
  - ANALYSIS says the balance check "is the one that tests the physics". It only checks mass bookkeeping: every agent deposits once a step, and decay is applied once. The `--turn 0` run passes it.
  - The "inside" check cannot fail except on NaN, because the kernel clamps positions (shaders.vl:111). The agent did not notice this.
  - README says as fact that the window hang "is the environment, not this program"; ANALYSIS says this was not confirmed.
- **Inconsistencies:** README promises "four verdicts" but lists and prints three. sim.vl:3 says "four kernels" but names three.

## 3. Task coverage
- ≥1M agents that sense, turn, move and deposit: **done** (shaders.vl:69-115).
- Trail diffuses and decays each frame, using atomics: **done**. Deposits go into a fixed-point `atomic<i32>` grid, followed by a blur/decay kernel and a clear kernel.
- Colour map: **done** (3 ramps, shaders.vl:173-195).
- Live keys for angle, distance, turn and decay: **done in code, never run**. The gain keys have a bug (§4).
- Mouse food and repel: **done in code, never run**.
- Headless checks of trail evolution and agents inside: **partial**; both checks are weak (§7).
- Shots after N steps: **done** (one shot at the end).
- Tests and README: **done**.

## 4. Correctness of the core
- **Kernels:**
  - The sense, turn and move logic is a reasonable Jones/Lague variant: a random turn size, turning toward the stronger sensor.
  - Sensor reads are clamped to the grid edge.
  - Wall reflection is correct: `PI - ang` for x, `-ang` for y (shaders.vl:107-110).
  - Hashing is per agent and per step.
  - The deposit `i32(u.trail.z * FIX)` is exact for the default deposit of 4.
  - The diffuse kernel sums trail plus dep over a clamped 3×3 window, then applies mix, decay and food. Clamping loses a tiny bit of mass at the borders: the run shows 4.600001e7.
- **Ordering:** sound throughout.
  - The dispatches run in one compute pass, in the order agents → diffuse → clear.
  - The two trail buffers alternate, selected by `cur`.
  - Draw comes after step in the same encoder, so it reads the new grid.
  - Uniform writes are queue-ordered.
- **Bug, gain keys (confirmed):** the default gain is 0.03 (tune.vl:38), but the `g`/`h` keys nudge by 0.25 within 0.25..8 (main.vl:164-167). The first press jumps to 0.25 or 0.28, about 9× brighter, and the original gain can never come back.
- **Overflow edge:** `--agents` up to 16M is accepted (main.vl:348). With a small `--size`, the i32 fixed-point cell overflows above about 524k agents in one cell.
- **Minor:**
  - `let old = atomicAdd(...)` is never used (shaders.vl:113).
  - `here` re-reads the centre cell, which the 3×3 sum already holds (shaders.vl:142).
  - `dep` has a `MAP_READ` usage it never needs (sim.vl:56).

## 5. Code quality
- **Strengths:**
  - a clean four-file split (main, sim, shaders, tune), good comments, clear names;
  - `inout self` and `inout pass` used idiomatically;
  - no `unsafe`;
  - errors use `Result`/`?` in `Sim::new_in`, matched in main.
- **Weak spots:**
  - `num()` (main.vl:31) silently falls back to the default on bad input.
  - Every default is written twice, once in `Arg::default` and again in `unwrap_or` (main.vl:321-361).
  - `on_key` is a 15-branch if-chain on characters.
  - The uniform is packed by hand into `[u32; 20]` by index. This is fragile, though it is tested.
- **Hand-rolled math:** only a PI constant (tune.vl:7), as expected.

## 6. Borrowing
The scaffolding comes heavily from `examples/gpu/fluid2d/sim.vl`:
- `snapshot_in` is copied verbatim (fluid2d sim.vl:416-438).
- `storage` and `zero` are identical.
- `kernel` and `run` are near-identical; only the entry point and the 1-D dispatch changed.
- Adapted from it: the `set_params`/`pack`/`zeros` pattern, building shaders from a shared COMMON prefix, the window loop, and the separate `Instance` for the surface.

The Physarum kernels, the atomic deposit design, the colour ramps and the checks are the agent's own.

## 7. Tests
- **The three `#[test]`s cover only trivia:** `nudge` clamping, the default ranges, and the `pack` word positions.
- **No CPU reference** covers the turn rule, the reflection, or the fixed-point deposit.
- **The headless checks miss a broken sense/turn step:** `--turn 0` produces a featureless disc and passes everything. A contrast or variance metric, or the fraction of cells above a threshold, would tell a network from a blob.
- **The inside check is a tautology** (shaders.vl:111). It passed even when the agent's own uniform bug sent every agent to one corner, as the agent reported.

## 8. Verdict
This is a working, fast Physarum: 1M agents at about 0.5–0.7 ms a step, an atomic deposit grid, correct diffusion and decay, and a picture that looks right. The code is tidy and idiomatic, built on fluid2d's scaffolding with its own kernels. Two things hold it back:
- **Unverified interaction:** the windowed mode, keys and mouse never ran, and the gain keys are broken.
- **Weak verification:** one check is a tautology, and the other is a conservation identity that does not depend on sensing.

The report is unusually candid about its weak spots, but it calls the balance check a physics test, which it is not.

**Grades:** result **B**, code **B+**, honesty **B+**.
