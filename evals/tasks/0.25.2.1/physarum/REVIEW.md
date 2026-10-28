> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: physarum (1M-agent slime mould)

## 1. Reproduce
`volec main.vl -o physarum` printed `ok: built physarum`. `volec test main.vl` gave `5 passed (-O0 and -O2 agree)`. All runs below went through `gpu-run --timeout 120`:
- `./physarum --headless --shot shot.ppm`: `worst rel err 2.5e-7: ok`, `1048576 of 1048576 inside the map: ok`, 0.95 ms a step (load 14), exit 0.
- `--steps 1000 --every 1000`: 0.65 ms a step, matching the claim exactly.
- `--agents 4194240 --size 2048 --steps 300`: check ok (2.4e-7), all agents inside, 7.6 ms a step at load 14. The claim was 5.4 ms over 1000 steps; this is plausible.

The shot is a well-developed vein network with a pleasant teal-to-yellow ramp and no seams at the edges.

## 2. Claims vs reality
All the numbers hold. The report says plainly that keys and mouse were not driven and that window frame times are not measured. One overstatement: under suggestions it says "I wrote my own" snapshot helper, but `snapshot_in` (sim.vl:248-268) is fluid2d's sim.vl:405-424 verbatim. The account of finding the hash bug from the picture is credible and a good lesson.

## 3. Task coverage
- At least a million agents: done (1,048,576 by default, up to 4.19M).
- Sense ahead and to both sides, turn, move, deposit: done, with atomics.
- Trail diffuses and decays each frame: done (3×3 blur, mix, decay).
- Colour map: done.
- Live keys for sensor angle and distance, turn, decay and diffuse: done, untested.
- Mouse food and repellent: done, untested.
- Headless trail-total evolution, agents inside, shots after N steps: done.

## 4. Correctness of the core
- Deposits use fixed-point `atomicAdd` (shaders.vl:93). The diffuse step reads src plus the deposit through `atomicLoad` (109) into a sum-preserving blur on the torus, then decays (122). Ping-pong bind groups alternate correctly (sim.vl:114-123, 169-181).
- The turn rule (79-88) differs slightly from Jones: when the front sensor reads lowest, it turns toward the larger side instead of randomly. This is acceptable.
- The trail-total recurrence is an exact, meaningful conservation check. It catches lost deposits and wrong bindings, but not wrong sensing, as the agent itself notes.
- "Agents inside" is nearly tautological: `wrapf` forces every position into [0, m) (shaders.vl:34-37), so only a NaN can fail it.
- The mouse term breaks the recurrence, so the check correctly runs without a pointer.

## 5. Code quality
The four modules (sim, shaders, tune, main) are clean and well commented. GPU state lives in one struct with per-parity bind groups. There is no `unsafe`, and std math is used (`h.cos()`, `sqrt` at sim.vl:196-199). Minor issues:
- `Tune::value_of` is dead code, and its comment "as text" is wrong (tune.vl:37-50).
- `clampf` is hand-rolled where f32 has `clamp` (tune.vl:98-100).
- `trail_total` duplicates its loop per branch (sim.vl:217-229) to get around `own.move_out`.
- The Pointer construction is duplicated (main.vl:180-188).
- A full-map `zeros` Vec is kept for the whole run (sim.vl:102-105), 16 MB at 2048², although a clear kernel exists.

## 6. Borrowing
Copied near-verbatim from fluid2d: `storage()`, `compute()` (fluid2d's `kernel`), `snapshot_in`, and the `pack`-to-words pattern. The WGSL and the simulation design are original.

## 6b. New features
None of them fit (single target, no depth). Readbacks use in-place `map_read` views, which is fine.

## 6c. Compiler bug
Not hit: the shader is bound to a `let` (sim.vl:63).

## 7. Tests
The 5 tests cover knob clamping, the key mapping, the recurrence's fixed point and `rel_err`. They are adequate for the CPU side but thin. Not tested:
- the WGSL hash or the turn rule;
- agent behaviour beyond the picture (e.g. that the mean heading spread or trail variance grows as a network forms).

## 8. Verdict
The quickest agent of the five, and it delivered a fast, beautiful, well-checked million-agent simulation. The conservation check is exact and honest about what it cannot see. The code is compact and readable, with a little dead code and copied helpers. The report is accurate. Its one slip is calling a verbatim-copied snapshot helper its own.

**Grades:** result **A**, code **B+**, honesty **A-**.
