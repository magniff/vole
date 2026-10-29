# ocean

Tessendorf's FFT ocean in vole, on the GPU (std::gpu, WGSL compute and
render), drawn into a window (std::window) with a camera you move.

Each frame: the Phillips spectrum's time evolution (a compute kernel: the
height, the two choppy displacements and the two slopes, from h0(k) and
w = sqrt(g k)), then a 2D inverse FFT of all five fields (16 radix-2
Stockham stages, row then column, ping-ponging between two buffers),
then the picture: a sky pass, and the water as a 255 x 255 quad mesh
displaced by the height and choppy fields, lit with Fresnel sky
reflection, a sun glint, foam where the surface compresses (the
Jacobian of the displacement), and fog toward the horizon.

## Files

- `main.vl`: the command line, the headless checks, the window loop,
  the unit tests.
- `ocean.vl`: the CPU side (the Phillips spectrum, the random amplitudes
  h0, the camera), the GPU side (`Ocean`: buffers, pipelines, `step`,
  `draw`, `snapshot_in`), and the FFT (`Fft`).
- `shaders.vl`: the WGSL: the spectrum kernel, the FFT stage, the sky
  and water shaders.
- `shot.png`: a headless frame from the start camera (960 x 540).

## Build and run

    volec main.vl -o ocean

    ./ocean                          the window (1280 x 720), N = 256
    ./ocean --frames 120 --shot f.ppm   quit after 120 frames; the last as PPM
    ./ocean --headless               the checks and timing, no window
    ./ocean --headless --shot f.ppm  the same, plus a picture (960 x 540)
    ./ocean --n 128                  a smaller grid (a power of two, 16 to 1024)
    volec test main.vl               the unit tests (-O0 and -O2)

Under the GPU lock during the eval: `tools/gpu-run --timeout 60 -- ./ocean ...`.

## Controls (window)

- W / S: forward and back; A / D: strafe; E / Q: up and down.
- Arrow keys: turn left and right, look up and down.
- P: pause the sea (the camera still moves); R: reset the camera.
- Escape: quit.

## What the headless mode checks

1. The inverse 2D FFT of a random 16 x 16 grid, five fields, against the
   definition (a direct DFT on the CPU). Tolerance 1e-3.
2. The height field at t = 3.7 s on the N x N grid: its mean (about
   zero) and its standard deviation against the target (0.45 m; a random
   spectrum, so within 25%).
3. Parseval: the field's mean square against the spectrum's sum of
   |H(k)|^2 (exact for the transform; tolerance 1e-3 relative).
4. Four sample texels of the height and of the slope dh/dx against direct
   sums over every mode on the CPU (tolerance 1e-3).
5. The frame time: the spectrum and the inverse FFT, timed over the steps
   (`--steps`, default 60), with the GPU waited on at the end.

The exit status is 0 only if the checks pass.

## What was verified, and how

Headless runs (through gpu-run), N = 256 unless stated:

    inverse FFT of 5 fields, 16 x 16 grid against the CPU DFT: max error 3.99e-06 (ok)
    height field 256 x 256 at t = 3.7 s: mean -3.19e-10 m, std 0.4193 m (target 0.45 m, ok)
    Parseval: mean square 0.175810 m2 against the spectrum's sum 0.175810 m2 (relative 1.39e-07, ok)
    4 sample texels against the direct sums: height error 2.29e-07 m, slope error 1.42e-07 m/m (ok)

The same checks at N = 16 pass (Parseval relative 7.5e-8, sample error
2e-7). The spectrum kernel's output was also compared texel by texel with
the CPU's H(k, t) before the FFT (largest difference 1.8e-8).

Unit tests (`volec test main.vl`): 5 passed, the same at -O0 and -O2:
the RNG's range, the wave numbers' symmetry, the spectrum's variance
(sum of 2 P(k) equals sig^2), H(-k) = conj H(k), and the camera basis
being orthonormal.

Frame time (headless, N = 256, 60 frames, gpu-run waited 0.0 s, load about
3): 0.41 ms a frame for the spectrum and the inverse FFT. Short runs
measured 0.6 to 4 ms; they are noisy (first frames, load).

The picture (`shot.png`) was inspected: lit water, the sun's glint on the
surface, the sky reflected, a horizon with fog.

The window: it builds and runs (`--frames 120`, 2560 x 1440 pixels on the
Retina display). The display was asleep during that run, so its frame
time (101 ms) is the timer's, not the GPU's, and I did not look at a
windowed frame or try the keys interactively.
