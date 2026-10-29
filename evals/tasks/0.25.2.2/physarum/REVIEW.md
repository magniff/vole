> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: physarum (1M-agent slime mould)

## 1. Reproduce
Built in a scratch copy: ok. `volec test main.vl` → 5 passed.
- `gpu-run --timeout 120 -- ./physarum --headless --steps 600 --every 300 --shot shot.ppm`, exit 0: `step 300: ... (off by 5.48e-8)`, `agents: 0 of 1048576 outside`, `0.543 ms a step`, both verdicts ok. The shot shows a clean branching Physarum network on a blue-to-cream ramp.
- My extra run `--steps 6 --every 1`: off by 1e-9 to 3e-8 per step, so the recurrence holds step by step.
- `--width 4096 --agents 6400 --steps 4 --every 2`: exits 101 with `sim.vl:198:13: gpu.limits: a dispatch of 147456 workgroups in one dimension; at most 65535`. See 4.

## 2. Claims vs reality
All numbers reproduce. The report's statement that the check "tests the atomics, ping-pong and clear" is somewhat overstated (see 4). Mouse and keys are honestly marked unverified, and the window frame time is correctly attributed to display pacing.

## 3. Task coverage
- At least 1M agents: done (1,048,576).
- Sense, turn, move, deposit: done.
- Diffuse and decay: done (compute, ping-pong, atomics).
- Colour map: done.
- Live keys for angle, distance, turn, decay and diffusion: done, untested.
- Mouse food and repel: done, untested.
- Headless trail evolution and agents inside: done.
- Shots after N steps: done (one, at the end).

## 4. Correctness of the core
- **Agent kernel** (`shaders.vl:44-91`): the Jones rule (straight / random / toward the stronger side), a hash RNG reseeded per frame, wall reflection, and a fixed-point `atomicAdd` deposit.
- **Diffusion** (100-123): reads `trail_in` and writes `trail_out`, so there are no races. The clamped 3×3 mean conserves mass: each cell is counted 9 times, including at the edges. It clears `dep` after reading it.
- **Ordering**: both dispatches share one compute pass, which the guide says is ordered (gpu#atomics). The ping-pong bookkeeping is right (`sim.vl:207-229`).
- **What the trail-total check covers**: every agent deposits the same amount wherever it is (`shaders.vl:89`), so the total follows keep·(total + N·d) *independently of agent behaviour*. Broken sensing, or agents reading the stale grid, would still pass. The check does verify that no atomic add is lost, the per-step clear, the conservation of the diffusion, and a single decay. With `--every 300`, keep³⁰⁰ ≈ 1e-11, so "predicted from the previous check" collapses to the steady state. The step-by-step run above shows it holds anyway. Agent behaviour is verified only by the picture, which is convincing.
- **Bug**: `--width` accepts up to 4096 (`main.vl:302`), but the clear kernel's 1-D `dispatch((cells+63)/64)` (`sim.vl:198`) exceeds 65535 workgroups above a width of about 2730 (reproduced above). std's message is excellent.
- **Minor**: the mouse mapping uses the `sz` captured at start (`main.vl:227`), which goes stale after a resize.

## 5. Code quality
The code is small and clean (three files, about 830 lines), with good comments and a `Params`/`pack` split. There is no `unsafe` and no dead code. `clampf` (`main.vl:32`) is hand-rolled; `f32::clamp` exists. The 15-key if-chain is verbose but clear.

## 6. Borrowing
`snapshot_in` is fluid2d's verbatim (`fluid2d/sim.vl:405-425`). The `Sim` struct, the window loop and `secs` follow fluid2d, as the report says. These are adapted, not wholesale copies.

## 6b. New in 0.25.2.2
The per-entry-point layouts are used correctly: `init` binds 0 and 2 while `clear` binds 0, 1 and 3 from the same text (`sim.vl:149-154`). But it compiles INIT twice (`sim.vl:139-140`); one `Shader` can back both pipelines (ocean does it). `adapter.limits()` was not used, and it would have caught the width bug. `gpu.unwritten` did not fire, because `reset` writes the uniform before the first submit.

## 6c. Mapped views
The views in `trail_total`, `agents_outside` and `snapshot_in` live inside their functions with no later submit. No dependency.

## 7. Tests
There are 5 unit tests: the recurrence's steady state, one step, `pack`, deposit rounding, and the clamp. They are cheap and tautology-adjacent. The headless check is meaningful for conservation but not for the agents' rule. Unchecked: keys, mouse, and widths above about 2730.

## 8. Verdict
This is the fastest finish of the round (6.4 min) and a clean, working million-agent simulation with a nice picture and an exact conservation check. The check is weaker than the report says, since it is blind to the agents' behaviour. There is a small dispatch-limit bug at large widths and an INIT module compiled twice.

**Grades:** result **A-**, code **A-**, honesty **A-**.
