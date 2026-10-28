# sph

A 2D smoothed-particle hydrodynamics fluid of 102 400 particles in a box
that tilts. The neighbour search runs on the GPU: a counting sort of the
particles by grid cell (the prefix sum is a compute kernel), then the
density, the pressure and viscosity forces, then the integration. The
particles are drawn in a window, coloured by speed.

Built with `volec main.vl -o sph` (vole 0.25.2), std only, no C.

## Run

```
volec main.vl -o sph
volec test main.vl                       # the CPU-side tests (4)
./sph                                    # the window (Ctrl-C or q / Esc to quit)
./sph --headless [--steps N] [--shot FILE.ppm]
```

Headless runs print the checks and exit 0 when they all pass. The default
is 8000 steps (0.64 s of simulated time), about 9 s on the GPU. Each
window frame runs 16 steps (`--steps N` in the window: 1 to 32).

The window and headless runs use the GPU; on this machine they were run
through the eval's `gpu-run` lock.

## Controls (window)

- Left button, drag: stir. The stir pushes the fluid toward the mouse's
  velocity inside a radius of 0.1 m.
- Right button, drag horizontally: tilt the box (the walls rotate, gravity
  stays down). Tilt goes to 0.5 rad at most.
- Left and right arrows: tilt in steps of 0.1 rad.
- Space: pause. `r`: reset to the starting block at rest.
- `+` / `-`: steps a frame, 1 to 32.
- `q` or Esc: quit.

The title shows the particle count, the steps a frame and the frame rate.
The colour is the speed: blue at rest, red at 4 m/s and above.

## What it is

- `main.vl`: the command line, the headless checks, the window loop.
- `sim.vl`: the GPU side: buffers, one compute pipeline per kernel, one
  step (clear, bin by cell, prefix sum, scatter, density, forces,
  integration) and the picture.
- `shaders.vl`: the WGSL, one kernel per shader, built from shared parts.
- `cpu.vl`: the constants, the starting lattice, the CPU references (cell
  of a point, counting sort, exclusive scan, sin and cos) and the tests.

The model: a 320 x 320 lattice of particles at spacing 2.2 mm, smoothing
length h = 2.4 spacings (about 18 neighbours), mass rho0 * spacing^2,
rest density 1000 (mass per area), pressure = c^2 (rho - rho0) with
c = 20 m/s, poly6 density, spiky pressure gradient, viscosity Laplacian
with a fixed coefficient, a fixed step of 8e-5 s (CFL about 0.3). The
walls are the box's four sides in its own frame: a particle is moved
there, clamped with a bounce (restitution 0.3), and moved back.

## Verified

Headless (`./sph --headless`, default run, output of the last run):

```
sph: 102400 particles, 8000 steps of 0.00008 s (0.640 s), grid 379 x 379 cells of 0.00528 m
step   2000: mean density 0.9892 x rest over all particles; bulk 1.0149 x rest over the 85% at 90% or more
step   4000: mean density 0.9383 x rest over all particles; bulk 0.9941 x rest over the 79% at 90% or more
step   8000: mean density 0.9206 x rest over all particles; bulk 0.9872 x rest over the 71% at 90% or more
sort: 102400 particles into 143641 cells; cell ids vs CPU: 0 differ; counts vs CPU histogram: 0 cells differ
prefix sum (GPU) vs CPU exclusive scan: 0 of 143641 entries differ
order: 0 entries not a permutation, 0 out of cell order; verdict ok
speed: mean 1.890 m/s, largest 10.724 m/s
fast: 332 above 5 m/s, 1 above 10 m/s; the fastest at (-0.8008, -0.4943) with density 0.991 x rest
escape: 0 particles outside the box (the tilt now -0.002 rad); verdict ok
density: mean 0.9872 x rest density at the end, verdict ok
```

- Sort and prefix sum: after the run, the GPU's cell ids, per-cell
  counts, exclusive prefix sum, and sorted order are read back and
  compared with the CPU, computed from the same positions. Zero
  differences over all 143 641 cells and 102 400 particles. The scan
  runs over 561 tiles in one workgroup, so it covers the multi-tile path.
- Density: the bulk mean (particles at 90% of rest or more) is 0.987 of
  rest at the end, checked within 5%. The all-particle mean is lower
  (0.92) because free-surface particles lack neighbours; that is expected
  for SPH and is printed, not checked.
- No escape: every particle lies inside the tilted box (checked in the
  box's frame, tolerance 1e-4 m) and none is NaN.
- Tests: `volec test main.vl`: 4 passed (scan, cell clamping, lattice
  inside the box, sin and cos), at -O0 and -O2.
- Window: `./sph --frames 300` runs (15.75 ms a frame at 16 steps a
  frame, measured through gpu-run). Its frame was checked as a picture,
  and the headless picture is `shot.png` in this folder.

Not verified: the mouse. The stir and the tilt by mouse and arrows
compile and run their code paths, but no interactive input was sent,
so their feel is untested.

## Limits

- Slow motion: 16 steps of 8e-5 s per frame is about 1/12 of real time.
  The step is limited by the sound speed (weakly compressible SPH needs
  c about 10 times the fluid's speed), and 100 000 particles at this
  spacing make each step about 0.85 ms.
- The grid covers [-1, 1]^2 so that the box in any tilt up to 0.5 rad
  stays inside it (the box's corners are 0.94 m from the centre).
