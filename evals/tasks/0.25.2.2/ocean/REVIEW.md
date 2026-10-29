> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: ocean (Tessendorf FFT ocean)

## 1. Reproduce
Built in a scratch copy: `volec main.vl -o ocean` → ok. `volec test main.vl` → 5 passed (-O0 and -O2 agree).
- `gpu-run --timeout 120 -- ./ocean --headless --shot shot.ppm`, exit 0:
  - `inverse FFT of 5 fields, 16 x 16 grid against the CPU DFT: max error 3.99e-6 (ok)`
  - `std 0.4193 m (target 0.45 m, ok)`
  - `Parseval ... relative 1.39e-7 (ok)`
  - `height error 2.29e-7 m, slope error 1.42e-7 m/m (ok)`
  - `0.405 ms a frame`
- `--n 16`: Parseval 7.52e-8, all ok. `--steps 600`: 0.323 ms a frame.
- The shot shows a lit sea with a Fresnel sky reflection, the sun's glint, and fog at the horizon. Foam is barely visible.

## 2. Claims vs reality
Every number in ANALYSIS/README reproduced exactly. The frame time is honestly qualified as noisy. "Spectrum kernel vs CPU H(k,t) 1.8e-8" came from a debug build and is not in the final program. Foam is called weak, which is fair. The window is honestly marked as not looked at.

## 3. Task coverage
- Phillips spectrum: done (`ocean.vl:54-83`, normalised so Σ2P = σ²).
- Time evolution on the GPU: done.
- Inverse FFT in compute passes with ping-pong buffers: done.
- Height field and normals: done. Normals come from FFT'd slope fields; choppy displacement is included.
- Displaced lit mesh: done. It has Fresnel sky reflection, a sun highlight, Jacobian foam (weak) and fog.
- Movable camera: done (WASD/QE/arrows), not driven by a person.
- Headless FFT vs DFT, statistics, shot: done.

## 4. Correctness of the core
- **Spectrum kernel** (`shaders.vl:24-45`): `h = h0(k)e^{iωt} + conj(h0(−k))e^{−iωt}`, `D = −i k̂ h`, `slope = i k h`. The renderer uses `x − λD` (`shaders.vl:132`), which with this D gives sharp crests, and the Jacobian (129) uses the same sign. It is consistent.
- **FFT stage** (53-73): textbook radix-2 Stockham. Stage t reads a or b by parity and 2·log₂N stages end in `a` (`ocean.vl:298-305`). All 16 stages are dispatched inside one compute pass, which is the efficient shape.
- **Water vertex shader**: a correct pinhole projection with reversed-free depth.
- **Checks**: strong. Parseval compares the GPU field with the CPU's Σ|H|² built from the same h0, so it tests the spectrum kernel and the FFT together. The four texels are compared with direct sums for height and dh/dx. Not checked numerically: the choppy fields Dx/Dz and the dh/dz slope (fields 1, 2, 4) beyond the random-input FFT test, so a sign error there would only show in the picture. The σ test (±25%) is loose but correctly labelled as random.
- **Minor**: in the shot block, `set_time(t)` at `main.vl:177` has no effect without a step, so the shot is at t ≈ 4.68 s, not 3.7 s. The mesh is a single, untiled 256 m patch.

## 5. Code quality
The code is clear and well commented, with no `unsafe`. `ocean.vl` mixes the CPU spectrum, the RNG, the camera, `Fft` and `Ocean` in 419 lines. That is acceptable, but a split would read better. The program defines its own `pub const PI` (`ocean.vl:12`) after the report learned `f64::consts::PI` exists; that is a hand-rolled-constant finding. The uniforms are packed as u32 words with `f32_to_bits` (`ocean.vl:340`), which is a little awkward but correct. It uses `Vec<gpu::Buffer>` and `Vec<gpu::BindGroup>` for per-stage uniforms (`ocean.vl:271-289`), which is fine.

## 6. Borrowing
`snapshot_in` is fluid2d's (`fluid2d/sim.vl:405`) with a depth texture added. `secs` and the window loop follow fluid2d's shape. These are adapted patterns, not copied blocks.

## 6b. New in 0.25.2.2
This is the best use of the per-entry-point layouts in this set. One `RENDER` module serves both the sky pipeline (binding 0 only) and the water pipeline (bindings 0 and 1) (`ocean.vl:323-330`). It also answers physarum's question: yes, one `Shader` can back two pipelines. Integer methods, storage formats and `adapter.limits()` were not needed. `gpu.unwritten` did not fire, because `set_time` and `set_camera` precede each submit.

## 6c. Mapped views
The view `got` (`main.vl:124`) of `o.fft.a` stays in scope while the timing loop (164-171) submits 60 steps that rewrite `fft.a`, and nothing refuses that. It is never read after line 158, so no check depends on it. The view in `fft_check` (80) has no later write. The agent's question (4.4) is exactly the soundness bug the orchestrator reproduced. Raising it was a valuable catch.

## 7. Tests
There are 5 unit tests that test something: RNG range, k symmetry, spectrum variance, Hermitian H(−k) = conj H(k), and an orthonormal camera basis. The headless checks are the strongest numerical validation in this round. Missing: choppy and slope-z fields, and anything about the render.

## 8. Verdict
This is a correct, efficient (0.3–0.4 ms) FFT ocean with checks that verify the maths to about 1e-7 and a good-looking frame, done in under 14 minutes. The report is honest and surfaced a real std::gpu soundness issue. The deductions are small: a hand-rolled PI, some untested fields, and a no-op `set_time` before the shot.

**Grades:** result **A**, code **A-**, honesty **A**.
