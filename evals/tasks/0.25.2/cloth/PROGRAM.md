# cloth

A hanging sheet of 64 x 64 particles simulated with position-based
dynamics on the GPU (std::gpu compute shaders in WGSL), drawn lit and
two-sided into a window (std::window). The sheet is pinned at its two
top corners, falls under gravity, is pushed by a wind, drapes over a
sphere and lands on a checkered floor. Normals are computed on the GPU.

## Build and run

```sh
volec main.vl -o cloth          # builds ./cloth
./cloth                         # the window
./cloth --headless --frames 600 # no window: run, print the checks
./cloth --headless --frames 600 --wind --shot wind.ppm
volec test main.vl              # the CPU-side #[test]s (6)
```

Options: `--n N` particles a side (8..256, default 64), `--iters N`
Jacobi iterations per substep (default 32), `--frames N` (window: quit
after N frames and print the mean frame time; 0 = never), `--shot FILE.ppm`
(headless: the last frame at 640 x 480; window: the last frame at window
size, with `--frames`).

## Controls (window)

- Left mouse button, press on a particle and drag: the particle nearest the
  pointer (within 0.12) follows the pointer on the plane through it, facing
  the camera. Release to let go.
- Space: pause and resume. R: reset. W: wind on or off.
- Left and right arrows: orbit the camera. Q or Escape: quit.

## What the simulation does

- Each frame is 8 substeps of 1/480 s. A substep integrates gravity
  (9.8), a gusting wind (acceleration 7 along +z, on or off) and damping
  (0.9995 per substep), then runs 32 Jacobi iterations of the distance
  constraints: stretch (rest h) and bend (rest 2h), each particle
  averaging its corrections over its constraints. The iterations ping-pong
  between two position buffers, so an even count always ends in the first.
  The sphere and floor are projected in each iteration.
- Pinned particles have inverse mass 0. The dragged particle is moved to
  the pointer each substep (kinematic) and is projected against the sphere
  and floor like the rest.
- Normals: central differences of the final positions, one-sided at the
  edges, computed by a compute kernel. The cloth is drawn from
  `vertex_index` (no vertex buffer) and is two-sided: a back face is
  flipped and darkened in the fragment shader.

## What the headless mode prints (and what it means)

- `constraint error after one frame`: the maximum and mean relative
  stretch of every edge after one frame, for 2 to 32 iterations. It must
  fall as iterations grow.
- Every second: strain (max and mean relative stretch), KE, PE, E = KE + PE
  (unit mass per free particle; PE is 9.8 times the sum of heights, so it is
  large and only its change matters), and a count of NaN or runaway values.
- `energy never rises after 1 s` (only without wind): no energy is injected.
- `worst edge at the end`: the grid position of the worst edge's start. It
  has been at the pinned top-left corner in every run.
- `stretch settles below 0.3 by the end`: a threshold I chose, not a
  physical law. See the limits below.
- `drag`: grabs the middle particle, moves it 0.25 along x over one second
  through the same path the mouse uses, and checks that it sits on the target.

## Verified (commands and results)

- `volec test main.vl`: 6 passed, at -O0 and -O2 (the sqrt, the camera's
  centre projection, a rest grid with no strain, a stretched edge, the
  edge count, and pick).
- `./cloth --headless --frames 600` (`headless-run.txt`): the constraint
  error falls from 0.0111 (2 iterations) to 0.0035 (32), mean 1e-5; no
  NaN; energy does not rise after 1 s; the worst stretch is 0.27 at the
  pinned corner (mean 0.7 percent); the drag lands exactly on the target
  (0.00000 away); after release the worst stretch is 0.37.
- `./cloth --headless --frames 600 --wind` (`headless-wind.txt`): no NaN;
  the stretch settles near 0.30 at the pinned corner, so the 0.3 check
  fails in this run (the energy check is skipped with wind).
- `./cloth --frames 120` (window): ran to completion, 8.28 ms a frame at
  1280 x 800 with physics on, measured through `gpu-run`.
- Images: `shot.png` (the default run) and `wind.png` (with wind), both
  converted with `tools/ppm2png.py`.

## Limits

- The solver is Jacobi with averaging, so it is soft: the stretch
  comes back only slowly, and the worst stretch sits at the pinned
  corners, where the sheet's tension is concentrated. More iterations help
  (16: 0.48, 32: 0.27 at the end of the default run) but cost time.
- The mouse drag, keys and the orbit were not driven by a real pointer or
  keyboard; the pick and the drag plane are checked by the unit test and
  the headless drag, which use the same functions.
- Picking reads the positions back from the GPU when the button is pressed
  (one synchronous read). The frame loop itself reads nothing back.
- No shadows, no self-collision, no tearing.
