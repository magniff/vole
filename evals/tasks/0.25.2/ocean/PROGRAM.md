# ocean

Tessendorf's FFT ocean in vole, on the GPU (std::gpu, WGSL compute and
render) and drawn in a window (std::window).

Each frame:
1. `evolve` (compute): the height spectrum H(k, t) = h0(k) e^{iwt} +
   conj(h0(-k)) e^{-iwt}, and the horizontal displacement spectra
   -i k/|k| H (times lambda), written to two buffers.
2. Inverse FFT (compute, ping-pong): one workgroup of 256 threads per row,
   then per column, radix 2 in workgroup memory. Buffers go a0 -> a1 -> a0
   and b0 -> b1 -> b0.
3. The mesh (256 x 256 vertices, 1 m apart) is drawn with depth: each
   vertex is displaced by the height and the horizontal displacement, its
   normal comes from the displaced neighbours, and its foam from the
   Jacobian of the horizontal mapping. The fragment shader does Fresnel
   reflection of a sky gradient, a sun glint and a haze to the horizon. A
   sky pass (full-screen, no depth write) is drawn first.

The initial spectrum h0 (Phillips, with Gaussian random phases from a hash
RNG) is computed once on the GPU by `init`, and again by `R` in the window.

## Files

- `main.vl`: the command line, the headless checks, the windowed loop.
- `ocean.vl`: the GPU side (`Ocean`: buffers, pipelines, bind groups, the
  recording of a frame, the read-backs, the PPM snapshot).
- `shaders.vl`: the WGSL (`init`, `evolve`, `fft`, the mesh and the sky).
- `cpu.vl`: sine and cosine (Taylor series; no C), a square root, the
  reference DFT, the camera matrices, and the `#[test]`s.

## Build and run

    volec main.vl -o ocean

Headless (no window): the checks, then a 640 x 360 picture:

    ./ocean --headless --shot shot.ppm
    python3 .../ppm2png.py shot.ppm shot.png

Options: `--n N` (grid cells, a power of two, 8..256; default 256),
`--frames N` (headless: frames stepped, default 60; window: quit after N
frames), `--seed S`, `--wind V` (window only: the headless run uses 10 m/s),
`--shot FILE.ppm` (headless, or with `--frames`).

Window: `./ocean`

Controls:
- W / S: forward / back; A / D: left / right; E / Q: up / down
- Arrow left / right: turn; arrow up / down: look up / down
- Space: pause the waves (the camera still moves)
- R: a new random spectrum (new seed)
- Esc, or the window's close button: quit

Tests: `volec test main.vl` (4 `#[test]`s: the trig and square root, the
reference DFT of a delta, and the camera's projection of its target).

## Headless output (this machine, Metal)

    fft: 16 x 16 cells, 4 lanes: the GPU against the CPU DFT, largest error 5.86e-6 (1.71e-7 of 34.2): ok
    fft: 32 x 32 cells, 4 lanes: the GPU against the CPU DFT, largest error 1.79e-5 (2.29e-7 of 78.0): ok
    height: 256 x 256 cells, 60 frames (1.97 s): mean 1.11e-10, rms 0.4846 m, skew 0.023, range -1.487 .. 1.686 m
    mean zero (k = 0 is not in the spectrum): ok
    Parseval: mean h^2 / sum |H_k|^2 = 1.000000: ok
    spectral sum at 16 points, worst |GPU - CPU| = 2.13e-7 m: ok

The checks: the FFT (both lanes) against an f64 CPU DFT on 16 x 16 and
32 x 32 grids; the height's mean (zero, as k = 0 is not in the spectrum);
Parseval, mean h^2 = sum over k of |H_k(t)|^2, with H recomputed on the
CPU from the read-back h0; and the height at 16 random cells against the
CPU sum of the spectrum at the same time (this covers evolve and both FFT
passes at 256 x 256).

Windowed, through the GPU lock: `--frames 120` ran at 8.5 ms a frame
(2560 x 1440 pixels, 256 x 256 cells).

## Known limits

- The grid is 256 x 256 cells for a 256 m patch (1 m cells); the FFT
  workgroup is 256 threads, so the grid is at most 256 (`--n` above that
  is refused).
- The amplitude is a constant in main.vl (`AMP`), tuned by hand to an rms
  of about 0.5 m at 10 m/s.
- The foam is a threshold on the Jacobian, with no advection: it sits on
  the folds rather than trailing behind them.
- Not verified on a second device; the picture was checked by reading the
  PNG only.
