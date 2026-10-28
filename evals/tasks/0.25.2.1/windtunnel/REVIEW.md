> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: windtunnel (D2Q9 BGK lattice-Boltzmann)

## 1. Reproduce
`volec main.vl -o windtunnel` printed ok, and `volec test main.vl` gave `7 passed (-O0 and -O2 agree)`. No `unsafe`. Through `gpu-run --timeout 120` at load 21-26:
- `--headless --shot shot.ppm`, about 4 s, exit 0:
  - mass: `114759.000 ... 114761.759 after 1500, 114764.399 after 3000 (relative drift 4.70e-5)`: ok;
  - shedding: `Strouhal 0.163 ..., amplitude 1.20e-1`: ok.
- `--headless --view vorticity --shot vort.ppm`: byte-identical to the agent's vorticity.ppm.
- `--headless --re 60`: Strouhal 0.160, amplitude 4.06e-3, ok.

The dye shot shows a clear Kármán street. The vorticity at Re 100 shows alternating vortices. At Re 60 the wake barely oscillates.

## 2. Claims vs reality
The numbers reproduce exactly. The report is unusually candid about the stability ceiling, the unresolved zero-output kernel, the untested controls, and the mass bound being an argument rather than a measurement. Overstatements:
- "Copying its shape, not its text". `kernel`, `run`, `zero` and `snapshot_in` (sim.vl:76-106, 262-282) are fluid2d's text.
- README:65 cites "the check's density range is 0.83 to 1.22". No such check exists in the code; it is stale.
- "Re 60: Strouhal 0.160 ... the check holds" is offered as corroboration. Williamson's fit gives about 0.135 at Re 60, and the amplitude of 4e-3 shows shedding has barely started. The fixed band of 0.14-0.20 with amp > 1e-4 (main.vl:123) is Re-independent and would not catch a wrong viscosity.

## 3. Task coverage
- D2Q9 BGK on the GPU: done.
- Flow from the left around obstacles drawn and erased with the mouse: done in code, never driven.
- Speed / vorticity / dye views by key: done (plus pressure).
- Reynolds-number control: done, but capped at 20-100.
- Stable at the defaults: yes at Re 100, though the ceiling sits just above the default.
- Headless mass conservation: done (closed box only).
- A known result: vortex shedding, St 0.163 at Re 100, a good match.
- Shots: done.

## 4. Correctness of the core
- Collide: in-place BGK, with `mac` written for the probe, dye and render. Correct.
- Stream (shaders.vl:65-97): pull scheme with halfway bounce-back at walls and obstacles, an equilibrium inlet, and an outlet that copies the cell's own post-collision value. Mass is conserved exactly in the closed box, so the observed linear drift (about 1.8e-3 per step) is plausibly f32 rounding bias, as argued.
- Kernels run in one compute pass. Metal's serial dispatch makes the order safe.
- Likely reasons for the Re ≈ 100 ceiling (not tested):
  - no-slip top and bottom walls meet a uniform equilibrium inlet, a corner singularity visible as strong vorticity at the top-left;
  - a non-absorbing outlet;
  - an impulsive uniform start.
  BGK at τ ≈ 0.57 and U = 0.1 is usually stable well beyond Re 100 at D = 24.
- **The zero-output kernel, a likely cause.** `Sim::new_in` never writes the uniform buffer (sim.vl:131-144). Every kernel begins `if (id.x >= p.nx || id.y >= p.ny) { return; }` (shaders.vl:40), and the first mass reading (main.vl:95) comes before the first `set_params`, which only `advance` calls. A moments kernel run there sees nx = ny = 0 and writes nothing, giving zeros on "two calls in a row" and non-zero values once stepping begins. This is the same uninitialised-uniform class sph hit this round. The CPU sum the agent switched to sidesteps it.

## 5. Code quality
A clear split (lattice, shaders, sim, main), and the tests sit beside the physics. Issues:
- `clampi` is hand-rolled (lattice.vl:47); `std::clamp` exists.
- "Clear all" builds a cylinder at (−1000, −1000) with r = 0 (main.vl:260).
- The window makes a second `gpu::Instance` just for the surface while the device belongs to `Sim`'s own instance (main.vl:233).
- `amplitude` and `strouhal` are fine.
- The 9 bind groups for ping-pong are explicit but correct.
- Branching inside the pass closure (sim.vl:219-231) is a reasonable answer to the move-out errors it describes.

## 6. Borrowing
- `kernel`, `run`, `zero`, `snapshot_in` and the `storage` helper are fluid2d's blocks, nearly verbatim.
- The lattice, boundaries, probe, Strouhal estimator and mask painting are original.

## 6b. New features
None of MRT, depth-only or `map_read_copy_in` fits; mapped views are read in place. It uses std math (`sqrt`, `floor`, `ceil`, `min`, `max`, `sin`).

## 6c. Compiler bug
Not hit. Every shader is `let`-bound (sim.vl:86, 153).

## 7. Tests
Seven tests: weights, equilibrium moments, opposite directions, Re↔ω round trip, the Strouhal estimator on a sine, stroke paint and erase, and disk area. The headless checks are genuine and able to fail: closed-box mass, and St at Re 100. Missing:
- a CPU reference step to compare the GPU stream and collide against;
- open-channel conservation (inflow equals outflow);
- a Re-dependent St band;
- any density or NaN guard.

## 8. Verdict
A working GPU LBM wind tunnel whose Kármán street and St = 0.163 at Re 100 are real physical validation, the strongest physics check of the round. The weaknesses are a stability ceiling right at the default, a Re-independent shedding band, verbatim fluid2d helpers, and a few stale or overstated lines. The report is exemplary in disclosing what failed. The zero-kernel mystery very likely comes from the uniform never being written before the first mass reading.

**Grades:** result **A-**, code **B+**, honesty **A-**.
