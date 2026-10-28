# windtunnel

A 2D lattice-Boltzmann wind tunnel (D2Q9, BGK collision) on the GPU, in vole.
Flow enters at the left at a fixed speed (Zou-He inlet), leaves at the right
(Zou-He outlet at density 1), and passes a cylinder (diameter 20 cells) that
you can draw and erase with the mouse. Top and bottom are walls.

## Build and run

    volec main.vl -o windtunnel
    ./windtunnel                                  # the window
    ./windtunnel --headless [--steps N] [--re R] [--view NAME] [--shot FILE.ppm]
    volec test main.vl                            # CPU-side tests

## Controls (window)

- Left drag: draw obstacle. Right drag: erase obstacle.
- `1` `2` `3` or `v`: view speed, vorticity, dye.
- `[` `]`: Reynolds number down / up by 10 (range 30 to 140, default 100).
- `-` `=`: brush radius (1 to 16 cells, default 4).
- `space`: pause. `r`: reset the flow. `c`: clear all obstacles. `o`: restore the cylinder.
- `q` or Escape: quit.

The window title shows Re, the view, the state and the frame rate.

Options: `--speed N` steps per frame (default 8); `--frames N` quit after N
frames and print the mean frame time; `--shot FILE.ppm` with `--frames`
writes the last frame.

## Headless checks

`--headless` runs two things:

1. A closed box (every edge a wall, cylinder inside) for 1500 steps. The sum of
   all populations must stay where it started. Reported: the largest relative
   drift at every 500 steps, with a threshold of 1e-4. Also the largest speed
   after the run.
2. The channel for `--steps` steps (default 12000). The transverse velocity 10
   cells behind the cylinder is recorded every step; its upward zero crossings
   give a Strouhal number St = f D / U. Also the largest speed and whether every
   value is finite.

The exit status covers the mass check and the stability check (finite, speed
below 0.2). The shedding line is reported but not gated; see ANALYSIS.md.

## What was verified (and how)

- `volec check` clean; `volec test main.vl`: 4 tests pass (lattice isotropy and
  weights, omega at Re 100, Re clamping, the Strouhal estimator on a synthetic
  sine).
- Closed box, 400 x 240 cells with cylinder, 1500 steps: total population
  sum 9.6e4 at start, largest relative drift 2e-5 (float32 rounding of the
  lattice weights, about 1e-8 a step). Threshold 1e-4.
- Empty channel (cylinder radius 0): largest speed 0.142 at the centreline, the
  Poiseuille value for a mean of 0.1; density stays at 1 +- 0.01.
- Closed-box perturbation decay, Re 30 vs Re 240: the largest speed falls to
  0.023 vs 0.037 (from about 0.042), so the Reynolds number reaches the collision.
- Windowed: 600 frames at 8 steps a frame, about 120 fps on the GPU with the
  lock (the 120-frame run hung once on the harness; 10 and 60 frames ran).
- Pictures: `shot_speed.png`, `shot_vorticity.png`, `shot_dye.png`.

## Known limits

- The cylinder's wake does not shed in these runs: at Re 100 the wake is steady
  and symmetric and the probe shows no clean periodic signal. The St check
  therefore fails. Details in ANALYSIS.md.
- Above about Re 150 the collision goes unstable at this resolution (NaN); the
  control stops at 140.
- Dye is advected semi-Lagrangian (bilinear), so it smears over long runs.
