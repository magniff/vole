# cloth

A cloth simulated on the GPU with position-based dynamics (PBD), in vole
(std::gpu compute kernels in WGSL, std::window for the window). A 64 x 64
particle sheet hangs from its two pinned top corners, falls under gravity,
drapes over a sphere, lands on a floor, and can be grabbed and dragged with
the mouse.

## Files

- `main.vl`: the entry point: the command line, the headless checks, the
  window loop (mouse, keys, frame timing).
- `sim.vl`: the GPU side: the buffers (made once), the kernels and bind
  groups, the per-frame uniform, `step` (the solver), `draw`, the readback.
- `shaders.vl`: the WGSL, one module per kernel with a shared prefix.
- `cloth.vl`: the CPU side: vectors, the camera and mouse ray, the pick,
  the drag target, the initial state, and the numbers the checks read
  (constraint error, energy, non-finite counts). Also the `#[test]`s.
- `cloth` (binary), `shot.png`, `grab.png`, `headless-run.txt`,
  `grab-run.txt`: the last build and the runs quoted in ANALYSIS.md.

## Build and run

    volec main.vl -o cloth          # `volec test main.vl` runs the 5 CPU tests

Headless (no window; the checks; a picture):

    ./cloth --headless --steps 600 --shot shot.ppm
    ./cloth --headless --steps 300 --grab --shot grab.ppm
    ./cloth --headless --steps 300 --gravity 0 --no-sphere   # the solver alone
    python3 .../tools/ppm2png.py shot.ppm shot.png

Options (headless): `--steps N` (frames of 1/60 s), `--size N` (N x N
particles, 8..128, default 64), `--iters N` (constraint sweeps a substep,
default 16), `--gravity G` (default 9.8), `--damping D` (what is kept of a
velocity per substep, default 0.99), `--no-sphere`, `--grab`, `--shot FILE`.

Windowed (the default; the GPU is shared, so keep runs short):

    ./cloth                          # size 64, 16 sweeps
    ./cloth --frames 120 --shot win.ppm   # quits after 120 frames

## Controls (window)

- Left button: press on the cloth to grab the nearest movable particle
  (within about 0.12 units of the ray); drag to move it; release to let go.
- Space: pause. R: reset the cloth. W: toggle gusting wind. S: toggle the
  sphere. Q or Escape: quit.

## What the simulation does

Each frame is `dt = 1/60` s, split into 4 substeps of `h = dt/4`:

1. predict: velocities get gravity, wind and damping; positions are
   extrapolated. A grabbed particle is held at the mouse's point.
2. solve: 16 sweeps. Each sweep runs 12 kernels, one per colour of the
   distance constraints (stretch and bend, along x and y; colours chosen so
   no particle is in two constraints of one colour), projecting that colour
   in place with the usual PBD correction split by the inverse masses. Then
   a collision kernel pushes particles out of the sphere and above the floor
   and applies the grab.
3. update: velocities are recomputed from the solved positions.

After the substeps, a compute kernel makes the normals from the grid's
central differences, and the picture draws the sheet (two-sided, lit,
normals from the GPU), the sphere (a procedural mesh) and the floor (a
checked plane).

## What was verified, and how

- `volec test main.vl`: 5 passed (the camera ray through the centre, a flat
  grid has zero constraint error, a stretched grid has its stretch as error,
  picking the particle on a ray, NaN and infinity counting).
- `./cloth --headless --steps 600` (`headless-run.txt`), exit 0: the
  constraint error (rms over every stretch and bend pair) falls from 0.062
  to 0.015; the total energy does not grow after frame 120 (the
  kinetic energy peaks on impact at frame 60, then decays to about 0); no
  NaN or infinity in 11 reads of positions and velocities; about 1 ms a
  frame of GPU time, measured headless with the GPU waited for.
- `./cloth --headless --steps 300 --grab` (`grab-run.txt`), exit 0: the
  grabbed particle follows its target to 0.004 units; the rest of the sheet
  stays bounded; the energy verdict is skipped because the hand does work.
- `./cloth --frames 120` in a window ran to completion through gpu-run.
  The display was asleep, so the frame times it printed are the timer's
  (100 ms), not the GPU's, and it is not evidence about the window.

Not verified: the mouse interaction by a person (only the grab path was
exercised headless); the window's look on a screen.

## Known limits

- The largest constraint error stays around 0.28 (in the top row next to
  the pinned corners, where the weight of the sheet goes, and at the sphere);
  the rms error is 0.015. More sweeps reduce the largest error (0.47 at 8
  sweeps, 0.28 at 16, 0.17 at 32), at a linear cost.
- PBD is not energy-conserving: the kinetic energy spikes on impact.
- The sheet starts 8% too long down the grid and bulges 0.25 towards the
  viewer; both are in `cloth::initial`.
