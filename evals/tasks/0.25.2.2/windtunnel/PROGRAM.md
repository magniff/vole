# windtunnel

A two-dimensional wind tunnel by the lattice Boltzmann method (D2Q9,
BGK collision with a regularized non-equilibrium stress), on the GPU
through std::gpu. Air comes in from the left at a chosen Reynolds
number, goes round a cylinder, and sheds vortices behind it. You can
draw and erase obstacles with the mouse, and watch speed, vorticity or
dye.

Built with vole 0.25.2.2.

```sh
volec main.vl -o windtunnel
./windtunnel                              # the window, Re 100
./windtunnel --re 150 --view vorticity    # another Reynolds number, view
./windtunnel --headless --check           # the checks: verdicts, exit 0 if all pass
./windtunnel --headless --shot shot.ppm   # the numbers, and a picture of the wake
./windtunnel --frames 600 --shot win.ppm  # 600 frames, the last one as a PPM
```

`--re` takes 20 to 250. The window is 1200 x 600 points; the grid is
640 x 320 cells, with a cylinder 40 cells across.

## Controls

| input | action |
|---|---|
| left drag | draw an obstacle (a solid disk along the stroke) |
| right drag | erase obstacles |
| `[` `]` | brush radius, 2 to 16 cells |
| `c` | clear all obstacles |
| `r` | reset the flow and put the cylinder back |
| space | pause / resume |
| `v`, `1` `2` `3` | next view; speed, vorticity, dye |
| `+` `=` `-` | Reynolds number up / down (x1.1), 20 to 250 |
| `q` / Esc | quit |

The title bar shows the Reynolds number, the view and whether it is
paused. Changing Re changes only the relaxation rate (a uniform), so it
takes effect at once. The clamp at 250 is where I stopped testing; I did
not try higher values.

## What it is

- [main.vl](main.vl): the command line, the window and its event loop,
  the headless checks, the brush.
- [sim.vl](sim.vl): the GPU side. Two population buffers and two dye
  buffers, swapped each step; the bind groups are made once; a step is
  one compute pass, a frame is one submission and one present.
- [shaders.vl](shaders.vl): the WGSL. `LBM` streams (pull) and collides
  in one kernel, `DYE` advects the dye with a Catmull-Rom sample, `PROBE`
  records the y velocity at one cell each step, `RENDER` draws the
  views.
- [flow.vl](flow.vl): the CPU side: the lattice constants, the
  equilibrium, the relaxation rate from Re, the disk mask, and the
  Strouhal number of the probe's series. Its `#[test]`s are the unit
  tests.

Boundaries: walls at the top and bottom; an inlet on the left at the
inflow speed (equilibrium); an outlet on the right with zero gradient;
obstacles (and the walls) by half-way bounce-back. The headless check
also runs a closed box (four walls).

## What was verified, and how

Run through the GPU lock, on the machine this was built on:

- `./windtunnel --headless --check` exits 0 and prints
  - the mass of a closed box over 1000 steps drifts by 2.2e-5 relative
    (accepted under 1e-4). The scheme conserves mass in exact arithmetic
    (collision conserves it, and bounce-back and streaming only permute
    populations); the residual is float32 round-off, which I did not
    separate out;
  - vortex shedding at Re 100: a Strouhal number of 0.168 over the second
    half of 40000 steps (accepted from 0.14 to 0.20; the known value
    for an unconfined cylinder at Re 100 is about 0.165). The probe's
    upward crossings in that window are evenly spaced (period about 3080
    steps), and the start-up transient (about 15000 steps) is excluded;
  - stability: finite everywhere, the largest speed 0.113 (lattice
    limit 0.577).
- Re 150, 200 and 250 also shed and stay finite over 40000 steps
  (Strouhal 0.18 to 0.19 in the same window). Re 60 does not shed with
  this blockage (12.5%) and plug inflow: its wake is steady.
- `./windtunnel --headless --view vorticity --shot ...` and
  `--view dye`: the pictures show the vortex street and the dye bands
  following the wake (converted to PNG and looked at).
- `volec test main.vl`: four unit tests (the equilibrium's moments, the
  relaxation rate, the Strouhal number of a sine, the disk's area).
- The windowed mode opens, steps and presents (checked with `--frames`
  short runs, through the lock). I could not look at the window itself,
  and the mouse painting was not exercised; it compiles and its
  arithmetic is simple, but treat it as untested.

## Known limits

- The dye is a passive scalar advected semi-Lagrangian style: it is
  diffusive, and it fades at the outlet.
- There is no lift or drag measurement; the only physical check is the
  Strouhal number.
- Re 100 takes about 20000 steps to settle into shedding. At 8 steps a
  frame that is about 40 seconds of window time from a cold start.
- The probe is written one sample per step, so the headless run submits
  one command buffer per step (about 0.3 ms a step wall time with the
  submission and readbacks; I did not measure the GPU time alone).
