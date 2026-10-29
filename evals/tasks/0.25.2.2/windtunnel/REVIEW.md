> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: windtunnel

## 1. Reproduce
`volec main.vl -o windtunnel`: ok. `volec test main.vl`: `4 passed (4 #[test]; -O0 and -O2 agree)`. Through `gpu-run --timeout 120`:
- `./windtunnel --headless --check`: exit 0 and three ok lines, 12.9 s wall.
- `--series s100.txt --view vorticity --shot vort.ppm`: mass 203536.000127 → 203531.480549 (drift 2.22e-5), Strouhal 0.1684, amplitude 0.0538, max speed 0.1130. The picture shows a clean alternating vortex street and the wall boundary layers.
- Extra runs:
  - `--steps 80000`: Strouhal **0.1783**.
  - A scratch variant with exact WGSL weights (below).

## 2. Claims vs reality
**Strouhal 0.168.** `strouhal` (flow.vl:33-61) uses the y velocity at a probe 2D behind the cylinder and 0.5D off the centre line (a good choice: this signal has the shedding frequency). It removes the mean over the **second half** (steps 20000–40000), counts upward zero crossings with linear interpolation, and takes period = (last − first)/(count − 1).
- In that window there are only **5 crossings (4 periods)**, spaced **3220, 3010, 2852, 2792**: not evenly spaced, and the period shrinks by 13 %.
- The probe amplitude per 4000-step block grows **0.0048 → 0.0127 → 0.033 → 0.048 → 0.054**. The shedding is still growing through the whole window.

So the README's "transient about 15000 steps is excluded" and "crossings evenly spaced (period about 3080)" do not hold for the run they cite. The "3080" comes from the older 24000-step `series100.txt`, whose second half is the small-amplitude linear-growth phase.
- At saturation (80000 steps, second half: 14 crossings, period 2760–2871) the value is **St ≈ 0.178**. That fits a 12.5 %-blocked channel better than 0.165 does.
- The check still passes either way (band 0.14–0.20), but the "0.168 matches the known 0.165" agreement is a coincidence of averaging over the transient.

**Mass drift 2.2e-5.** It is not random round-off.
- The f32 sum of the weights written as 7-digit decimals (shaders.vl:24) is 1 − 2.235e-8. Every collision scales mass by that factor, and 1000 steps gives exactly −2.235e-5.
- With `4.0/9.0, 1.0/9.0, 1.0/36.0` (scratch) the drift becomes +7.3e-6, again equal to that set's f32 weight-sum error.

**Can the mass check fail?** Yes:
- it compares real readbacks (main.vl:125-137);
- because the bias is linear in the number of steps, it would fail at about 4500 closed steps;
- it would catch gross streaming or bounce-back index errors.

It is weak, though: the closed box starts at rest (ux = 0, uy ≈ ±1e-3; sim.vl:97-107). At rest `f_k = f_opp(k)`, so a direction-swap bug in bounce-back would barely move the mass.

Other claims (stability, max speed, views, Re 150–250 shedding) are consistent with what I saw. I did not re-run Re 60 or 150–250.

## 3. Task coverage
- D2Q9 on the GPU: done. BGK is regularized; disclosed.
- Flow from the left: done.
- Draw and erase obstacles with the mouse: done but untested. After a resize the mouse mapping goes wrong: `sz` is never updated (main.vl:360 vs :366-367).
- Speed, vorticity and dye views with keys: done.
- Reynolds control: done (±10 %, 20–250).
- Stable by default: done.
- Headless checks for mass and vortex shedding, and shots: done; see section 2 for their strength.

## 4. Correctness of the core
- The LBM kernel (shaders.vl:36-93) is solid:
  - pull streaming with half-way bounce-back from the cell's own opposite population;
  - an equilibrium inlet and a zero-gradient outlet;
  - a regularized collision `feq + (1−ω)·Π^neq` that conserves mass and momentum exactly.
- `omega_for` is right (tau = 3ν + ½).
- Dye: Catmull-Rom semi-Lagrangian advection by the new velocity.
- Ping-pong bind groups match their parity. Serial dispatches in one compute pass order LBM → DYE → PROBE.
- One submit per step in the headless run is a deliberate trade for a per-step probe index.
- The vorticity colour comment (shaders.vl:165, "blue clockwise") is reversed for the y-down grid: red is clockwise on screen.

## 5. Code quality
- Clean files: flow for CPU physics, shaders, sim for the GPU, main. Good comments and `#[pure]` helpers.
- Ownership workarounds left duplication:
  - `record` repeats its whole body per parity (sim.vl:216-225);
  - `draw` duplicates the render pass (:233-245). fluid2d puts the `if` inside one closure.
- Small items:
  - The variable `first` is dead (main.vl:275, :316).
  - The NaN test is `x - x != 0.0` (sim.vl:273) where `is_finite` exists.
  - A manual clamp at main.vl:220-226 (integer `clamp`).
  - `3.14159265` (flow.vl:133) next to `std::math::PI` (:122).
- No `unsafe`.

## 6. Borrowing
Heavier than elsewhere, as small verbatim blocks from fluid2d's sim.vl: `kernel`, `storage`, `run` (sim.vl:74-93), `snapshot_in` (:299-319), the `g_<kernel><parity>` layout, the `zeros` buffer, and `verdict`. These are adapted helpers, fine in themselves. The physics is original.

## 6b. New in 0.25.2.2
- Four modules (COMMON plus each kernel, the fluid2d pattern). One module serving all pipelines was possible, but the binding numbers would need reworking.
- No storage textures (f32 storage buffers suit LBM). Integer `clamp` and `is_finite` were missed.
- `gpu.unwritten` did not fire: `set_params` precedes every record. No `adapter.limits()`.

## 6c. Mapped view across a submit
None. `stats` and `probe_series` map, read, and drop inside the function, and the closed-box `reset` writes after those views are gone.

## 7. Tests
- Unit tests: feq moments, omega, the Strouhal of a pure sine, disk area.
- The headless physics checks are the right idea but weakly specified:
  - the Strouhal window does not test that the amplitude has saturated;
  - the mass test runs a fluid at rest;
  - nothing checks drag or lift, or the mass flux through the open tunnel.
- Mouse painting is untested.

## 8. Verdict
The strongest physics of the round: a correct regularized LBM with sensible boundaries, a nice vortex street, stable to Re 250, and real GPU-side checks. But the validation story is overstated. The Strouhal number is averaged over 4 periods of a still-growing transient, with uneven crossings, while the report calls them evenly spaced with the transient excluded. The mass drift is a systematic weight-truncation bias, not noise. Both checks pass for partly the wrong reasons.

**Grades:** result **B+**, code **B+**, honesty **B-**.
