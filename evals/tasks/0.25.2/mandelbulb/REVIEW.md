> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: mandelbulb

## 1. Reproduce
- Build ok, check 0 errors, `volec test main.vl`: 9 passed.
- `gpu-run --timeout 60 -- ./mandelbulb --headless`: `view 0 (Mandelbulb, 320x180): 1.34 ms … mean luma 0.269, spread 0.070`.
- `--headless --check`: views 0 to 2 at 1.14, 2.11 and 0.70 ms, all `ok`, `repeatable: … identical`, exit 0.
- `--fractal box --check`: 3.85, 3.15 and 2.11 ms, all ok.
- 640x360 shots: bulb view 1 at 3.99 ms, box view 0 at 8.43 ms, `--power 3` view 0 at 4.57 ms (load 11 to 12).
- I looked at the images: a recognisable Mandelbulb, and a grainy, aliased Mandelbox close-up. Power 3 gives a recognisably different, noisier bulb.
- The window run was not reproduced (no windows).

## 2. Claims vs reality
The headless results and timings hold. My 640x360 view 0 was about 4.6 ms against the claimed 2.4 to 2.5, at higher load. The "Not verified" list (live mouse and keys) is candid.

Inaccuracies:
- **"There is no way to get an allocator in a test … allocating code cannot be tested" is false.** `volec guide testing` documents `#[test] fn t(gpa: Gpa)`, and deferred and terrain use it. Suggestion #3 rests on this.
- Comments at `main.vl:2` and `scene.vl:168` refer to a `march.wgsl` file that does not exist.

## 3. Task coverage
- Mandelbulb distance estimate: **done**.
- Second fractal (Mandelbox): **done**.
- Soft shadows: **done**.
- Ambient occlusion: **done**.
- Fly-through with mouse and keys: **done** (auto-flight is a smooth Lissajous path; manual WASD flight has no easing). Not verified live.
- Live power knob: **done**.
- Headless fixed views to PPM with timing: **done**.

## 4. Correctness of the core
The WGSL is textbook and correct:
- Bulb distance estimate `0.5·log r·r/dr` with the standard `dr` update (`shader.vl:42-59`).
- Box fold, sphere fold with minR² = 0.25 and fixedR² = 1, and `dr·|s|+1` (`:62-82`).
- Tetrahedron normals (`:91-98`) and Quílez-style soft shadow and AO (`:101-124`).
- Hit threshold proportional to t; the y-flip of the screen coordinates is right.

Nits:
- AO is applied twice: the ambient term gets ao² and the direct light is also multiplied by ao (`:168-169`).
- The bulb's orbit trap is r and the box's is r², so their palettes differ.

CPU side:
- The uniform layout of six vec4s matches `uniforms()` (`scene.vl:169-183`).
- Per-frame `write_buffer` then submit is correct.
- `bench` waits idle before and after the timed loop (`render.vl:71-82`).

Weak check: "neither black nor flat" (mean luma 0.03 to 0.97, spread > 0.04) passes almost any non-empty render. "Two renders identical" is near-tautological for a deterministic shader. Nothing checks that shadows, AO or the power actually change the picture, though a headless comparison would be easy.

## 5. Code quality
- The module split (main, render, scene, shader, ppm) is sensible.
- `Renderer::new(dev: sink, queue: sink)` is idiomatic. `inout` and the `&` call marks are right; `Result` and `?` are used. No `unsafe`.
- Hand-rolled `sin64`, `cos64` and `sqrt64` (`scene.vl:11-44`), as expected.
- Small smells:
  - `m.get("fractal")` is parsed three times (`main.vl:248-249`).
  - `same_bytes` reimplements slice equality.
  - Every key event calls `win.request_frame()` (`main.vl:212`) on top of the per-frame request.

## 6. Borrowing
- The window loop's fps title and `--frames` mean, and the PPM writer (`ppm.vl:6-17`), follow fluid2d's `main.vl` and `snapshot_in` closely: adapted, with some lines verbatim.
- The shader and camera code are original.

## 7. Tests
- **The nine tests:** sin, cos and sqrt; camera orthonormality; preset views; knob clamping; WASD moving along the view; drag turning the camera and P starting the fly-through; uniform layout; luma statistics. That is good CPU coverage.
- **Missing:** any test of the image beyond luma, and the PPM writer (which the agent thought untestable).

## 8. Verdict
A complete, good-looking result with correct distance estimators and the full feature list. The code is clean apart from stale comments and small duplication. The report is honest but contains one confident false claim about test allocators that would mislead the language team.

**Grades:** result **A-**, code **B+**, honesty **B+**.
