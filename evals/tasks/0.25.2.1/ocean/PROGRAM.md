# ocean

Tessendorf's FFT ocean in vole, on the GPU. Each frame: the Phillips
spectrum's time evolution (a compute pass), a 2-D inverse FFT of three
fields (height, and the two horizontal displacements that make the waves
choppy) as 14 Stockham radix-2 compute passes ping-ponging between two
buffers, then the water mesh drawn straight from the field buffer: each
vertex is displaced, takes its normal and a Jacobian (for foam), and the
fragment shades it with a Fresnel sky reflection, a sun glint and foam.
The mesh is 128 x 128 quads over a 200 m patch, drawn 3 x 3 tiles.

The initial spectrum h0 (Phillips for an 8 m/s wind, Gaussian noise from
a fixed seed) is generated once on the CPU; everything per frame is GPU.

## Build and run

```sh
cd evals/tasks/0.25.2.1/ocean
/Users/magniff/workspace/tachyon/target/volec main.vl -o ocean
./ocean                          # the window (run it on a screen)
./ocean --headless               # the checks' numbers (no display)
./ocean --headless --shot shot.ppm   # plus a 640 x 400 frame as PPM
./ocean --headless --bench       # the time for a frame's GPU work
./ocean --n 256                  # a finer grid (a power of two, 8..512)
./ocean --frames 120             # window: quit after 120 frames
volec test main.vl               # the CPU-side #[test]s
```

To view the shot: `python3 .../tools/ppm2png.py shot.ppm shot.png`.

## Controls

| input | action |
|---|---|
| left drag | orbit: yaw and pitch |
| arrow left / right | yaw |
| arrow up / down | pitch (lower / higher) |
| `w` `a` `s` `d` | move the look-at point (along and across the view) |
| `+` / `-` | zoom in / out |
| `[` / `]` | choppiness lambda down / up (0 to 2.5) |
| space | pause / resume the clock |
| `r` | reset the camera and the clock |
| `q` / Esc | quit |

## What it verifies (headless)

- The FFT: an 8 x 8 forward 2-D transform against the DFT by definition
  (largest error 2e-5 on values of order 1), and the inverse of it
  against 64 x the input (same run).
- The height field at t = 3 s on the 128 x 128 grid: the GPU's value at 8
  sample points against the CPU's direct sum over all k (error 3e-7 on an
  rms of 0.43 m).
- Parseval: mean over the grid of h^2 against the sum over k of |H|^2
  (ratio 1.000000).
- The height statistics: mean 1.6e-10 m, rms 0.433 m, max |h| 2.0 m.

`volec test main.vl`: 5 tests (Phillips zero at k = 0 and damped at high
k, the wave-number folding, the Stockham stage writes every index exactly
once for each stage size, the RNG's range, the patch length).

## What was not verified

The windowed mode was only run for 120 frames through gpu-run, with the
display occluded (so the timer fallback ran it); its look and its frame
rate were not checked on a visible window. Keys and mouse were not
exercised. Foam is subtle at the chosen choppiness: it appears only where
the Jacobian drops below about 0.2.
