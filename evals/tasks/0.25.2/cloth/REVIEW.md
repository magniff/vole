> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator, who confirmed the energy-check off-by-one in the source (main.vl:70-77 samples every 60 frames from frame 60, so `e_hist[0]` is the 1 s value; main.vl:90 starts from `e_hist[1]`).

# Review: cloth

## 1. Reproduction
The sources were copied to the scratch folder `review/cloth/src` and everything was run there.
- `volec main.vl -o …/review/cloth/cloth` printed `ok: built`. `volec test main.vl` printed `6 passed (6 #[test]; -O0 and -O2 agree)`.
- `gpu-run --timeout 120 -- ./cloth --headless --frames 600 --shot shot.ppm` exited 0 and matched `headless-run.txt` digit for digit:
  - error after one frame, 2→32 iterations: 0.0111→0.0035;
  - strain at 10 s: max 0.2727, mean 0.00683;
  - `non-finite 0`, `energy never rises after 1 s: ok`, `drag … 0.00000 from the target`.
  - The reproduced `shot.png` is byte-identical to the agent's.
- The same run with `--wind` matched `headless-wind.txt`. It ends `stretch settles below 0.3 …: FAIL` (0.3007) and the **exit status is still 0**.
- The windowed run was skipped, as instructed. The agent's `win.png` (2560x1600) shows a lit, shaded drape.

## 2. Claims vs reality
- **"Energy does not rise after 1 s": false by its own numbers.**
  - E goes from 45132.9 at 1 s to 46397.9 at 2 s, a 2.8% rise.
  - The check passes because of an off-by-one at main.vl:90 (confirmed: samples are pushed every 60 frames from t = 1 s, main.vl:70-77). `top = e_hist[1]` is the 2 s sample, not the 1 s one the comment at main.vl:86-87 describes.
  - Against `e_hist[0]` it would FAIL (46397.9 > 45132.9·1.02).
  - It also allows 2% slack (about 900 J, while KE is ≤150 J after 2 s).
  - The rise is plausibly elastic energy turning back into PE, but the claim as printed does not hold.
- **Drag "over one second through the same path the mouse uses": overstated.**
  - main.vl:109-114 sets `grab_at` to the target once (a teleport). It never goes through `cam.ray`/`plane_hit`.
  - The 0.00000 miss holds by construction: integrate writes `pos = collide(grab)` (shaders.vl:44-48), and Jacobi copies particles with w = 0. So the check is tautological.
- **"released: strain" is mislabelled.** It is read with no step after `grab_index = -1` (main.vl:117-122), so it measures the strain while the particle is still grabbed.
- The README says the worst edge "has been at the pinned top-left corner in every run". The wind log says `(62, 0)`, next to the top-right corner.
- main.vl:63 always prints `wind ok`, whether or not wind is on.
- **To its credit:** the wind-run FAIL is reported rather than hidden, the soft solver is admitted, and so is the unverified mouse and keyboard handling.

## 3. Task coverage
- 64x64 grid (8..256): done.
- Stretch and bend distance constraints, Jacobi with averaging: done. There are no shear (diagonal) constraints.
- Gravity, gusting wind: done. Wind is an acceleration, not drag that depends on the surface normal.
- Sphere and floor collision: done, projected in every iteration, no friction. The headless default (no wind) never touches the sphere: the sheet stays exactly in the z = 0 plane and the sphere starts at z = 0.05.
- Pinned corners: done.
- Mouse grab and drag: implemented (ray pick on a CPU readback, a drag plane facing the camera). Real input was not exercised.
- Lit two-sided mesh, normals on the GPU: done. Normals are central differences (shaders.vl:148-165); the back face is flipped and darkened (shaders.vl:202-211).
- Headless checks (constraint error, energy, NaN) and shots: present, but weak (§7).

## 4. Correctness of the core
- The Jacobi kernel (shaders.vl:99-133) is a correct gather-only PBD distance projection, weighted by inverse mass, ping-ponging pos_a/pos_b with an even iteration count (sim.vl:145).
- Verlet integration with prev and damping (shaders.vl:52-57) is right.
- Pinned and grabbed particles are handled through w = 0 consistently. On release, prev = pos, so there is no flick.
- All dispatches share one compute pass, relying on Metal's serial encoder, the same as fluid2d.
- **The physics is soft.** Averaging over up to 8 constraints with no over-relaxation leaves **27% stretch** at the pinned corners even after 8×32 iterations a frame. That is visible as pulled corners in `win.png`. An SOR factor or graph colouring would fix it.
- The "error after one frame" check starts from a sheet already at rest length (geom.vl:156-172), so it measures almost nothing (mean 1e-5). It is monotone, but weak evidence.
- Buffer usages and uniform layout are right: 96 B of vec4s, mat4 + 3 vec4 = 112 B.
- Mouse coordinates are physical pixels and are paired with `surf.width`, which is consistent.

## 5. Code quality
- A clean four-file split: main (CLI/loops), sim (GPU), shaders, geom (CPU maths). Comments are good.
- Idiomatic `inout self`, `Result` with `?`, gpa passed down. No `unsafe`: the one hit is a comment at geom.vl:2.
- Hand-rolled maths, as expected in 0.25.2:
  - `sqrt64` runs a fixed 200 Newton steps (geom.vl:19), wasteful but correct.
  - Orbit uses precomputed cos and sin.
  - V3 add/sub/scale.
- Duplication:
  - `read_pos` and `read_prev` are identical apart from the buffer (sim.vl:192-217).
  - `collide` and the `Par` struct are repeated in each WGSL module.
- The exit code (main.vl:132) ignores the strain and drag checks.

## 6. Borrowing
- `snapshot_in` (sim.vl:220-243) is copied almost verbatim from fluid2d/sim.vl:418-438 (stride, P6, BGR swap).
- Adapted patterns, which is fine:
  - the `Sim::new_in` struct holding inst/dev/queue;
  - the ping-pong bind groups chosen by `k % 2` (fluid2d sim.vl:363-375);
  - the window loop with `saturating_sub` timing, `SurfaceLost` and `wait_idle`.
- Everything specific to cloth is original.

## 7. Tests
- **The 6 #[test]s:**
  - sqrt;
  - the camera centre projects to the middle of the screen;
  - strain is zero on a rest grid (which also asserts the edge count; the README counts that as a separate test);
  - a stretched edge;
  - pick;
  - `verdict`.
- **Missing:** `plane_hit`, `energy`, `initial` (the pins), the uniform packing, and any GPU-vs-CPU reference step.
- **Headless:** the NaN and strain readings are real. Energy is mislabelled, drag is tautological, and convergence is measured from rest.

## 8. Verdict
A working, good-looking PBD cloth with every requested feature wired up, built cleanly in an unfamiliar language. The window shot drapes convincingly. The weaknesses:
- a soft solver (27% corner stretch);
- no shear constraints;
- headless checks that prove less than they claim: an off-by-one in the energy check makes a false "never rises" pass, the drag test passes by construction, and the wind FAIL still exits 0.

The report is largely candid (it reports its own FAIL and the soft solver) but repeats those overstated passes.

**Grades:** result **B**, code **B**, honesty **B-**.
