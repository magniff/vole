# sph

A 2D smoothed-particle hydrodynamics fluid, 102,400 particles (320 x 320 start block), on the GPU with std::gpu and WGSL kernels. Each substep rebuilds a cell grid by counting sort (clear, count, prefix sum, scatter), then computes density, pressure and viscosity forces, then integrates (gravity, mouse stir, walls). Particles are drawn coloured by speed.

## Build and run

    volec main.vl -o sph
    ./sph --headless --shot shot.ppm        # checks, then numbers, then a PPM frame
    ./sph --frames 120                      # window for 120 frames, then the frame time
    volec test main.vl                      # CPU tests (kernel normalisation, scan, packing, view transform)

The headless run takes about 20 s on the GPU for the default 20,000 substeps (1 s of fluid).

## Controls (window)

- Left and right arrows: tilt the box (gravity turns with it)
- Left mouse button, drag: stir (pushes particles along the mouse's velocity)
- Space: pause, r: reset, q or Escape: quit

## What the headless run prints and checks

- Grid, on the start block: cell counts and each particle's cell against a CPU histogram; the starts against the exact CPU exclusive scan; the sorted order (each particle once, cells in order, each in its cell's slots).
- Every 500 substeps: mean density, bulk fraction, centre height, top speed.
- Escape: all positions finite and within the box, and the deepest wall penetration below one smoothing length.
- Settling: the last two density checks agree within 1%, and the mean is within 5% of rest density.

## Verified (see ANALYSIS.md)

- Headless default run (102,400 particles, 20,000 substeps = 1 s of fluid): all checks ok. Final mean density 100.7% of rest, deepest penetration 0.00017 (smoothing length 0.005).
- CPU tests: 5 of 5 pass at -O0 and -O2.

## Not verified

- The windowed picture at 2560 x 1440 looks wrong (box off-centre and squashed, flat band at the top). The 720 x 720 headless frame looks right. Not resolved.
- Windowed frame time: this machine's window showed no frames during the check (occluded/asleep), so no frame time was measured.
