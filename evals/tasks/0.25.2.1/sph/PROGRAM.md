# sph: smoothed particle hydrodynamics on the GPU

102,400 particles of water in a 2.0 x 1.4 m tank, 2D SPH. The neighbour
search runs on the GPU as a grid built by counting sort: cell ids, a
histogram (atomics), an exclusive prefix sum (one workgroup, tiles of 256),
a scatter into cell order. Then density (poly6), pressure (spiky gradient,
symmetric form, p = k (rho - rho0), no tension), viscosity, gravity, the
mouse's stirring force, and integration with walls. Particles are drawn as
discs coloured by speed (blue slow, white fast).

## Build and run

    volec main.vl -o sph
    ./sph                                  # the window
    ./sph --headless --frames 120 --shot shot.ppm   # checks and a PPM shot
    volec test main.vl                     # the CPU-side tests (8)

The headless run is on the GPU: run it through `tools/gpu-run`.

## Controls (window)

- Drag with the left mouse button to stir the fluid.
- Left and right arrows tilt the box (up to 0.9 rad); gravity stays down on the screen.
- Space pauses, r resets to the start lattice, q or Escape quits.
- `--substeps N` caps the substeps per frame (default 80; a frame's time is
  split into steps of at most 0.25 ms). `--frames N` quits after N frames and
  prints the mean frame time (with `--shot` it also writes the frame).

## What the headless run checks

- Sort: the GPU's cell ids, histogram, prefix sum (starts), and order are
  compared with the CPU, at the start and after the run. Result: 0 wrong entries.
- Prefix sum: the scan kernel on 100,003 counts, against the CPU exclusive
  sum, exact. Result: 0 wrong.
- Density: the mean density is printed every 30 frames. The verdict needs the
  end value within 5% of rest and the last 30 frames moving it by under 1%.
- Escapes: no particle outside the box or non-finite. Result: 0.

The run's tilt and mouse path are scripted (`scripted` in main.vl), so the
headless numbers are reproducible.

## What was verified and how

- `volec test main.vl`: 8 tests (lattice inside the box and 102,400 particles,
  mass gives rest density, grid size 134 x 94, gravity under tilt, window centre
  maps to box centre, tilted box fits the window, exclusive scan, check_sort).
- `./sph --headless --frames 120 --shot shot.ppm` run through gpu-run: all four
  checks ok (output in ANALYSIS.md). shot.png was viewed: the tilted box, the
  fluid pooled to one side, speed colouring and a free surface.
- A short windowed run (`--frames 120`, gpu-run): it quit by itself, and its
  window frame (window.png, 2560 x 1440) was viewed: the box at rest, untilted.
  The display was occluded during this run, so its frame time is the 10 fps
  timer, not a GPU measurement.

## Known limits

- The mean density sits about 3% above rest (1032 kg/m^2 vs 1000): the weakly
  compressible equation (sound speed 15 m/s) compresses the bottom under
  gravity. The check tolerance is 5%.
- Viscosity is a Laplacian approximation with the 2D constant; MU = 0.005 is
  tuned for stability at SIM_DT, not for physical water.
- Within a cell the sort's order is not deterministic (atomics), so float sums
  can differ in the last bits between runs.
- A frame at 67 substeps costs about 39 ms on this machine, so the window runs
  at a fraction of real time at 60 Hz; the substep cap bounds it.
