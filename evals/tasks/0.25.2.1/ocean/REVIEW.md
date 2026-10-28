> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: ocean (Tessendorf FFT ocean)

## 1. Reproduce
`volec main.vl -o ocean` printed `ok: built ocean`. `volec test main.vl` gave `5 passed (-O0 and -O2 agree)`.

`gpu-run --timeout 120 -- ./ocean --headless --shot shot.ppm --bench` (load 10.2) exited 0 and printed:
```
FFT vs DFT, 8 x 8 grid ...: largest error 1.97e-5: ok
height field at t = 3 s, 128 x 128 grid: GPU vs CPU sum at 8 points, largest error 2.81e-7 (of rms 0.433 m): ok
Parseval: mean h^2 / sum |H|^2 = 1.000000 (1 exactly): ok
128 x 128 grid: 0.15 ms a frame ...
```
The shot shows a convincing lit sea with a sun glint at the left and haze. No foam is visible, and the sky above the horizon is a flat colour.

## 2. Claims vs reality
Every number reproduces exactly (the run is deterministic), and the bench gave 0.15 ms against the claimed 0.14. The report states the weak points itself:
- foam is nearly invisible;
- h0 is computed on the CPU once;
- the bench is CPU time with a wait, not a GPU timestamp;
- the window was never seen.

Its account of the inline-shader compiler bug is accurate. I found no overstatement. One small understatement: it lists a "length" test that is in fact tautological (see 7).

## 3. Task coverage
- Phillips spectrum: done (CPU, once; standard practice).
- Time evolution on the GPU: done.
- Inverse FFT as compute passes with ping-pong: done (Stockham, 2·log2 n passes).
- Height field and normals: done. Normals are finite differences in the vertex shader, not spectral.
- Displaced, lit mesh with sky reflection (Fresnel) and a sun highlight: done.
- Foam: partial (the Jacobian term exists but is barely visible).
- Movable camera: done (keys and drag), not exercised.
- Headless FFT vs DFT, statistics and shot: done, plus a GPU-vs-CPU height check and Parseval.

## 4. Correctness of the core
- Evolution is h0·e^{iωt} + conj(h0(−k))·e^{−iωt} (shaders.vl:35-37), and Dx/Dz = −i·k̂·h (41-42). Both are correct.
- The Stockham stage (72-81: `j = 2·tid − (tid & (ns−1))`, twiddle sign by direction) is correct, and the result lands in `a` because the stage count is even.
- Displacement x − λD gives sharp crests. The Jacobian is taken from the displaced mesh (135). The reversed-z-free projection maps depth to 0..1 (142-144).
- Minor: the clear colour (ocean.vl:293) is a flat sky, so the `sky()` gradient appears only in reflections. The mesh ends 300 m out while the fog reaches 1200 m (shaders.vl:171), so the horizon is a hard cut.
- Each FFT stage is its own compute pass (ocean.vl:272-279). That is safe, though one pass would do.

The checks are real. The 8-point CPU sum covers both the evolution and the IFFT, and the forward-then-inverse round trip is a genuine FFT test.

## 5. Code quality
The split into spectrum/GPU/camera (ocean.vl), WGSL (shaders.vl) and CLI/checks (main.vl) is clear, with good comments and no `unsafe`. Issues:
- `check_height` returns a 7-tuple whose last element is a dummy `0.0`, and `total` is unused at the call site (main.vl:110, 152, 196).
- The headless run creates three devices (main.vl:67, 112, 212).
- The xorshift `Rng` (ocean.vl:33-45) duplicates std::random. The vec3 helpers are fine, since std has no vec type.
- std float math is used throughout (`ln`, `cos`, `tan`).

## 6. Borrowing
`render_ppm` (main.vl:156-179) adapts fluid2d's `snapshot_in` and adds a depth target. The frame loop follows fluid2d. The FFT and spectrum are original.

## 6b. New features
Depth uses `desc.depth(...)` and `PassDesc...with_depth` (ocean.vl:236, 293-294). MRT and depth-only passes are not needed, and `map_read_copy_in` was not needed.

## 6c. Compiler bug
This is the agent that found it. About 4 build-run cycles and a probe were lost before binding to a `let` (ocean.vl:199-200, 209-210) fixed it. The report gives a minimal repro. This is not held against it.

## 7. Tests
- `stockham_stage_writes_every_index_once` is a good structural test.
- The Phillips and wave-folding tests are good.
- `checks_cover_the_patch_length` (main.vl:408-413) only asserts that a constant is positive.

The GPU path is tested by the headless checks, which are strong. Gaps: nothing checks the normals or foam numerically, the imaginary part of the IFFT output (which should be about 0) is not checked, and no camera test exists.

## 8. Verdict
A correct, well-verified FFT ocean with real numerical checks and a good-looking frame. The weak spots are foam and the horizon. The code is tidy apart from a tuple-return wart and one empty test. The report is exemplary: precise, it reproduces, and it isolated a real compiler soundness bug.

**Grades:** result **A-**, code **B+**, honesty **A**.
