> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: mandelbulb

## 1. Reproduce
Built a scratch copy: `volec main.vl -o mandelbulb` printed `ok: built mandelbulb` (vole 0.25.2.2). `volec test main.vl` gave `4 passed (4 #[test]; -O0 and -O2 agree)`. All runs went through `gpu-run --timeout 120`:
- `./mandelbulb --headless --frames 20`, exit 0: view 0 1.80 ms, view 1 2.73 ms, view 2 2.01 ms, view 3 2.59 ms. The luminance and colour lines match `shots/headless_640x360.txt` exactly (for example view 0: mean 88.2, spread 25.8, 396 colours).
- `--view 3 --shot`, `--view 1 --power 12 --shot`, `--view 0 --power 2 --shot`: all three are recognisable fractals.
- Is the timing real? At 1280x720, view 1 takes 7.27 ms, against 2.7 ms at 640x360. With `--no-shadows --no-ao` it drops to 1.83 ms. The cost follows the work, so the GPU really does it.

## 2. Claims vs reality
Every number holds within the noise of a re-run. The report is careful about what it did not check: the window was never visible, keys and mouse were never pressed, and the timings are wall clock. "Mandelbox bounding radius 5 is a guess" is fair. View 3's flat right edge and partial corner pieces suggest the sphere at camera.vl:102 clips the box. Nothing is overstated.

## 3. Task coverage
- Mandelbulb, distance estimate, sphere tracing: done.
- Second fractal (Mandelbox): done.
- Soft shadows and ambient occlusion: done, both switchable.
- Smooth fly camera with mouse and keys: done (an exponential ease toward a goal pose). The automatic fly-through is buggy (section 4).
- Power changed live: done (arrow keys).
- Headless fixed views to PPM, with timing: done.

## 4. Correctness of the core
- The WGSL is textbook. `bulb_de` (shader.vl:32-52) is Quilez's estimate with `dr = n r^(n-1) dr + 1`, guarded `acos`/`pow`, and an orbit trap. `box_de` (54-76) is the standard box fold, sphere fold (minR² 0.25), scale and shift.
- The march clips to a bounding sphere and uses a distance-relative epsilon. Normals use the tetrahedron trick. The soft shadow and AO are Quilez's.
- The uniform block is 28 floats (112 bytes) and matches `pack` (camera.vl:88-109). The up vector f×r is right.
- **Synchronisation:** `bench` (main.vl:92-110) writes the uniform, records and submits each frame back to back, then calls `wait_idle`. That is a valid throughput measure.
- **Bug:** the automatic fly-through (main.vl:364-372) rotates the wrong way. It moves the goal on a circle at angle a = 0.11·clock (x = 2.6 sin a, z = −2.6 cos a). Facing the origin from there needs yaw = −a, but the code adds +0.12·dt to yaw. The view drifts off the fractal at about 0.23 rad/s, so the bulb leaves the frame within a few seconds. `cam.fly(0.0, 0.0, 0.0, dt)` at :368 does nothing.
- **Weak check:** the headless check (main.vl:211: spread ≥ 4 and ≥ 8 colours) only rejects a flat picture. A wrong estimator that still hits something would pass.

## 5. Code quality
- Three files with a sensible split: camera/CPU state, WGSL, and GPU plus CLI.
- `Tracer` owns device, queue and pipelines. Methods use `inout self` well. The comments explain why.
- No `unsafe`, and std Float methods throughout. The only hand-rolled clamps are integer and float clamps that std now has: main.vl:284-286 (`look.iters`) and camera.vl:144 (pitch).
- `--power` is parsed twice (main.vl:173 and :485).
- main.vl (500 lines) mixes input, the window, bench and CLI; acceptable at this size.

## 6. Borrowing
- `snapshot` (main.vl:122-161) is fluid2d's `snapshot_in` PPM loop with luminance and colour statistics added.
- `secs` and the window loop shape come from fluid2d.
- The shaders, camera and input code are its own. "Copied the shape, not the code" is accurate.

## 6b. New in 0.25.2.2
- It uses two WGSL modules (scene and blit). The blit could have lived in the same module as a second pipeline, but separate is reasonable.
- No Rgba16Float scene target (it renders Bgra8Unorm and stretches it), no integer methods (the clamps above), no `adapter.limits()`.
- `gpu.unwritten` never fired: `set()` always precedes `draw`.

## 6c. Mapped view across a submit
None. `px` in `snapshot` lives only until the function returns, and no submit follows while it lives.

## 7. Tests
- Four CPU tests (orthonormal basis, yaw-0 direction, uniform packing, ease convergence) cover camera.vl well.
- Nothing tests the estimators, the march, or input handling.
- The headless check is a flatness test only. A CPU reference of `bulb_de` at a few points, or a hit/miss mask for a known view, would make it real.

## 8. Verdict
A polished result in a short time: both fractals with shadows, AO and an orbit-trap palette look good, and the timings are real and scale with resolution. The main defect is the automatic fly-through, which turns away from the fractal. The headless check is too weak to catch shading or estimator regressions, and the window path was never exercised. The report is precise and admits every gap.

**Grades:** result **A-**, code **B+**, honesty **A**.
