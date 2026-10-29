# sph: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

**Works (headless):** 102,400 particles (320 x 320 start block), grid by counting sort (clear, count, one-workgroup prefix sum, scatter), density, pressure and viscosity forces, integration with walls, colour by speed. Default `./sph --headless --shot shot.ppm` (20,000 substeps = 1 s of fluid) ends with `overall: grid ok, fluid ok`:
- Start-block grid checks: cell counts and particle cells vs a CPU histogram (0 differ); prefix sum vs the CPU exact exclusive scan (0 of 40,402 differ); counting-sort permutation, cell order and slot ranges (0 problems).
- Mean density 100.7% of rest at the last checkpoint, bulk fraction 99%, last two checks within 0.23%.
- Deepest wall penetration 0.00017 against smoothing length 0.005; all positions finite.
- Timing: 0.87 ms a substep, submit-and-wait, checks left out, under contention. An earlier run at the same size measured 0.41 ms.

**Not working or unverified:**
- The windowed snapshot at 2560 x 1440 (`./sph --frames 120 --shot window.ppm`) is wrong: the box is off-centre (its centre sits near x 1110, y 976, not 1280, 720), squashed vertically, with a flat uniform yellow band across the top. Cause not found. The 720 x 720 headless frame looks right. Needs a look before window mode counts as done.
- No windowed frame time: the window showed no frames during the check (occluded or not displayed), so frame times are unmeasured.
- Tilt and stir are implemented but not checked visually.

**Verified how:** `volec test main.vl` passes 5 of 5 at -O0 and -O2 (poly6 normalisation, exclusive scan, gravity turning with the box, screen/box round trip, cell coverage). `volec check` reports 0 errors. Headless run through tools/gpu-run.

## 2. How you worked

- `volec guide` (full), `guide gpu`, `guide window`, `guide testing`: read in full. `--find` not used.
- Read examples/gpu/fluid2d (main.vl, sim.vl) and the voxel WGSL scan. grep on compiler/std is blocked by a hook, so I used `volec query show`/`items` there.
- `volec check` after edits via the hook: frequent. `volec fix` not run by hand; the hook rewrote `&mut x` to `&x` several times.
- `volec query context` not used. `volec probe` not used.
- Debugging was by printed checkpoints in the headless run, not by probe.
- Builds: many `volec main.vl -o sph` runs, each under a second.

## 3. What went well

- Builds were sub-second, and the first full build compiled with no errors.
- The WGSL kernels (`var<workgroup>` scan, `atomicAdd`, `atomicMax` on bitcast floats, `discard`, `select`) compiled and gave correct results first time.
- The CPU/GPU agreement checks matched exactly on the first run.
- `volec test` is fast; the `gpa` parameter convention is clear.

## 4. What went badly

Most of the time went to my own physics errors, not to vole. Listed because they matter for the report:
1. Stiffness: I set `k = rho0 * c^2`, but the pressure is `k * (rho - rho0)`, so `k` must be `c^2`. Pressure was 1000x too high; the first blow-up. Fixed.
2. The start lattice sat at 98.8% of rest density, so the clamp `max(p, 0)` left the block unable to hold itself up. Fixed by calibrating the particle mass.
3. Viscosity kernel: I used the poly6 Laplacian, which is negative for r < h/sqrt(3). At 0.4h spacing the lattice sum was anti-diffusive, so more viscosity made things worse. Replaced by `40/(pi h^5) (h - r)`, positive over the support. A real SPH pitfall.
4. Stability bound: explicit viscosity stiffness is about `nu * 5.3e5`, so `dt * nu * 5.3e5 < 2`. At dt = 5e-5 that means nu < 0.038. nu = 0.2 and 0.1 blew up (density 280x and 45x rest). Default nu = 0.02.
5. Coincident particles: `d/r` at r = 0 gives NaN. Guarded with `r2 < 1e-14`.

Other problems:
- A run with an unstable parameter (dt 5e-5, nu 0.1) held the GPU until its 200 s gpu-run timeout. The first full-size run looked hung for about 2.5 minutes at 0% CPU; it was the blow-up collapsing particles into one cell, so each particle scanned almost all particles.
- Timing was inconsistent for the same program (0.08 ms vs about 1 ms a substep at 4k particles). Later runs settled at 0.41 to 0.87 ms at 102k. The cause was not established.
- Piped output is invisible until exit (`| grep | tail` shows nothing while running), so a long run looks dead. I redirected to a file and polled it.
- I asked to kill my own runaway process and the auto-mode classifier refused it. The process ended at its gpu-run timeout. One queued run waited 332 s for the GPU lock.
- The check-after-edit hook rewrote my `&mut` to `&` and changed files between my reads ("changed on disk since you last read it"). Harmless, but I lost track of the file state. A diff in the hook message would help.
- `sed -i` with no backup suffix fails on macOS (BSD sed); I used python. Not vole.
- `let w = 1280.0` is f64 and mixing with f32 gives "expected 'f64', got 'f32'". The fix (`let w: f32 = ...`) is in the help line, but the first error was confusing.
- Start lattice points landed exactly on cell boundaries, so CPU and GPU floor-based cell indices disagreed (1000 counts). Moved the block offset off the boundary (0.0333). A trap for any check comparing floor-based indices across CPU and GPU.

## 5. The language

- Fought me: writing `&mut x` for inout (Rust habit; the hook fixed it, but I wrote it several times); f64 defaults on literals; `let` where `var` was needed (hook fixed it).
- Liked: `&x` for inout is short; `gpa` injection in tests; Rust spellings caught instantly; `volec check` as fast feedback; one WGSL module per kernel makes bindings explicit.
- Missing or unclear: a way to tell which kernel is slow (no per-kernel GPU timing); a flush option for piped stdout.

## 6. Suggestions, ranked by time saved

1. Flush stdout (or print unbuffered) when it is a pipe. This would have saved several long waits and the "is it hung?" guessing.
2. A per-kernel GPU timer (e.g. `volec gpu profile`). I could not tell which kernel was slow, and the 0.08 vs 1 ms swing went unexplained.
3. Document the explicit-viscosity stability bound and the SPH pitfalls in the gpu docs: the poly6 Laplacian is negative at short range; the stiffness is `c^2`, not `rho0 c^2`.
4. Show the diff when the hook rewrites a file (`&mut` to `&`), since it changes files the agent has just read.
5. Give the f64-vs-f32 literal error a one-line `let x: f32` hint in the message.
6. Note in the std docs that CPU and GPU float division can put a boundary point in different cells.
7. gpu-run: `proc.wait()` after SIGKILL has no timeout, so a child stuck in the driver would hold the lock forever. I did not see this happen, but the path is there.

## Open items

- Windowed 2560 x 1440 snapshot looks wrong (box off-centre and squashed). Needs a look.
- No windowed frame time measured.
- Stir and tilt not checked visually.
