> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: mandelbulb (Mandelbulb and quaternion Julia, raymarched)

## 1. Reproduce
I copied the sources to a scratch folder. `volec main.vl -o mandelbulb` printed `ok: built mandelbulb`, and `volec test main.vl` gave `7 passed (-O0 and -O2 agree)`. All GPU runs went through `gpu-run --timeout 120` at load 9.1:
- `--headless --size 384 --frames 10 --view K --shot vK.ppm` for K = 0, 1, 2: hit shares 63.9% / 100.0% / 75.1% and brightness 0.300 / 0.166 / 0.327, exit 0. My v0.ppm is byte-identical to the agent's.
- `--headless --size 1024 --frames 4`: 10.31 ms mean (claimed 9.3). With `--no-shadows --no-ao`: 5.74 ms (claimed 4.9). Both are close, given the load.

The pictures show a detailed, lit Mandelbulb (view 0), a close-up of a power-5 bulb (view 1), and a shelled quaternion Julia set with orange interior glints (view 2).

## 2. Claims vs reality
Every number reproduces. The report is short and accurate.
- Minor: it calls the timing "GPU timing". It is wall time over submitted frames followed by `wait_idle` (main.vl:210-221), which is a fair throughput figure, not a GPU timer.
- The test named `ppm_header_and_checksum_are_stable` (main.vl:499) tests only the header length, not the checksum.
- The untested controls and the stalled windowed timing are stated plainly.

## 3. Task coverage
- Mandelbulb raymarched in a fragment shader: done.
- Second fractal (quaternion Julia set with a drifting c): done.
- Distance estimation: done (the bulb's and Julia's DEs are both the standard Quilez forms, shader.vl:25-66).
- Soft shadows: done.
- Ambient occlusion: done.
- Smooth fly-through camera with mouse and keys: partial. It is an eased orbit camera whose target WASD/QE move (camera.vl:85-91), so the eye can enter the set. Input was never exercised.
- Power changeable live: done (`[` `]`, written to the uniform every frame).
- Headless fixed views to PPM, with timing: done.

## 4. Correctness of the core
- Sphere tracing starts at the bounding sphere (radius 2), uses a 0.8 under-step, a hit threshold proportional to t, a tetrahedron normal, and Quilez's soft shadow and five-tap AO. All are correct.
- The uniform layout (28 f32s) matches WGSL alignment: `eye` falls at offset 16.
- The hit check is honest. It re-renders with a debug flag that outputs white on a hit (shader.vl:149-152) and counts white pixels. The pass thresholds are weak, though: hit share > 5% and brightness > 0.02 (main.vl:227). A wrong normal, broken AO or a power that has no effect would still pass. Nothing checks that two powers give different images.

## 5. Code quality
Three files with clear roles (camera, shader, main) and good comments. No `unsafe`. It uses std math throughout (`sin`, `cos`, `exp`, `clamp`, `sqrt`, `abs` methods); nothing is hand-rolled. Issues:
- The windowed loop re-implements `draw()` inline (main.vl:358-365 duplicates 77-86).
- The comment at main.vl:118-120 describes `hit_share` but sits above `digits`.
- `header_len`/`digits` (main.vl:122-135) recompute a length that `format_in(...).len()` already gives.
- Headless prints the Julia constant and "power 8.00" for every view, including the Julia view.
- `secs()` is a one-line wrapper.

## 6. Borrowing
- `snapshot` (main.vl:95-116) is fluid2d's `Sim::snapshot_in` almost verbatim.
- The CLI, window-loop and `secs` shapes follow fluid2d.
- The shader, the camera and the checks are original.
- The report says "the window, cli, PPM and GPU setup came from the reference example", which is accurate.

## 6b. New features
None of MRT, depth-only or `map_read_copy_in` fits the task (the snapshot reads a mapped view in place). It uses std math well.

## 6c. Compiler bug
Not hit. `make_pipeline` binds the shader to a `let` (main.vl:72).

## 7. Tests
Seven CPU tests: an orthonormal basis, eye distance and look direction, fly direction, pitch/zoom clamps, easing convergence, power clamp, and header length. They are good for the camera. Gaps: nothing checks the uniform packing against the WGSL struct, the DE (a CPU DE at a known point), or the key mapping. The headless check is a smoke test.

## 8. Verdict
A polished, good-looking raymarcher, done in about 6 minutes, with both fractals, shadows, AO, live power and a sensible headless mode. The core shading is textbook-correct. The checks are a smoke test, and the fly camera is an orbit-with-moving-target that was never driven. The report is brief, accurate and modest.

**Grades:** result **A-**, code **B+**, honesty **A**.
