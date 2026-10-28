# windtunnel

A two-dimensional lattice-Boltzmann wind tunnel on the GPU, in vole
(std::gpu for the compute and the picture, std::window for the window).
D2Q9 lattice, BGK collision. The flow comes in from the left at a fixed
speed and goes out on the right; a cylinder sits in the stream, and you
can draw and erase obstacles with the mouse. The picture shows the
speed, the vorticity, the dye (coloured bands released at the inlet), or
the pressure.

## Build and run

    volec main.vl -o windtunnel      # the build; `volec test main.vl` runs the tests
    ./windtunnel                     # the window (960 x 480 points)
    ./windtunnel --headless          # no window: the checks, then exit (0 = both pass)
    ./windtunnel --headless --shot shot.ppm --view vorticity
    ./windtunnel --frames 120 --shot win.ppm   # the window for 120 frames, then quit
    ./windtunnel --re 60             # any of these: the Reynolds number, 20 to 100

Convert a PPM with `python3 /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/tools/ppm2png.py shot.ppm shot.png`. Options: `--re RE` (default 100), `--view NAME` (speed,
vorticity, dye, pressure; default dye).

## Controls (window)

| key | what it does |
|---|---|
| left mouse drag | draw an obstacle |
| right mouse drag | erase obstacles |
| `[` `]` | smaller / larger brush (1 to 16 cells, default 6) |
| `1` `2` `3` `4`, `v` | speed, vorticity, dye, pressure (`v` cycles) |
| `+` / `=`, `-` | Reynolds number up / down by a quarter (20 to 100) |
| `c` | clear all obstacles |
| `o` | put the cylinder back |
| `r` | reset the flow (the obstacles stay) |
| space | pause or resume |
| `q` or Esc | quit |

The Reynolds number is printed on the terminal when it changes; the
window has no text overlay.

## The model

- Grid 480 x 240 cells. The cylinder is 24 cells across, its centre at
  x = 120, y = 120. Lattice units: the inflow speed is 0.1 cells a step.
- Reynolds number Re = U D / nu, with D = 24 and U = 0.1, so
  nu = 2.4 / Re and omega (= 1/tau) = 1 / (3 nu + 1/2). Re 100 gives
  omega = 1.75.
- A step is collide (BGK, with the obstacle's cells left alone), then
  sample (the probe), then stream (the populations move one cell;
  bounce-back at the top and bottom walls and at obstacles; the left
  edge is an equilibrium inflow, the right edge a zero-gradient
  outflow), then the dye (semi-Lagrangian advection, bilinear).
- Four steps a frame in the window.

## Limits

- Stable at the default Re 100 and up to about Re 100 at this grid. I
  measured Re 110, 120, 135, 150, 200 and 250 to blow up (the amplitude
  of the probe goes far above the inflow speed). The `+` key stops at
  100, and `--re` above 100 is refused. Re 100 with a 32-cell cylinder
  also blew up, so this is not just the relaxation rate.
- The inflow is a fixed equilibrium and the outflow zero-gradient; the
  pulses that leave the outflow are not absorbed, and the closed box
  starts with an impulsive stop, which launches acoustic waves of about
  17 % density (the check's density range is 0.83 to 1.22).
- I could not look at the window: it was occluded when I ran it. The
  mouse and key handling compiles and the window loop runs (see below),
  but I did not drive them by hand.

## What was verified, and how

Commands, all through the GPU lock (`evals/tasks/0.25.2.1/tools/gpu-run`):

1. `volec test main.vl`: 7 `#[test]`s, at -O0 and -O2: the D2Q9 weights
   sum to 1; the equilibrium carries its density and momentum; opposite
   directions are opposite; the Reynolds number round-trips through
   omega; the Strouhal estimator returns the frequency of a known sine
   (4.8 for a 50-step period); a stroke paints and erases the mask; a
   disk has the right area.
2. `./windtunnel --headless`, default Re 100:
   - mass, closed box (walls on all four sides, the cylinder inside),
     3000 steps: the fluid's total density starts at 114759.000 (the
     number of fluid cells) and reads 114761.759 after 1500 steps and
     114764.399 after 3000. The relative drift is 4.7e-5, 1.8e-3 a
     step. The check passes at 1e-4. Bounce-back and the collision
     conserve mass exactly, so this drift is float32 rounding (the
     bound is about 1e-7 of a cell's mass per step, times 115k cells,
     which is 1.4e-2 a step; the observed value is below that). A
     real leak would be larger. This is an argument, not a measurement
     of the rounding.
   - shedding, open channel, 6000 transient steps then 12000 sampled:
     the vertical speed 2D behind the cylinder crosses its mean with
     Strouhal number 0.163 (known: about 0.164 at Re 100; I used the
     published 0.16 to 0.17 as the band). Peak-to-peak amplitude 0.12
     (about 0.6 U). I did not check the amplitude against a reference.
   - shot: `shot.ppm`, the dye at step 18000 (`shot.png`): a Karman street
     behind the cylinder, the dye bands rolled up into eddies.
3. `./windtunnel --headless --re 60`: Strouhal 0.160, amplitude 4e-3,
   and `--re 90`: Strouhal 0.162, passing; so the shedding check holds
   at both.
4. `vorticity.png`: the alternating sign of the shear layers behind the
   cylinder, at default settings.
5. `./windtunnel --frames 60`: the window opens, runs 60 frames (4 steps
   each) and exits. The window was occluded during this run (the
   display was not shown), so the 101 ms a frame it reports is the
   occlusion timer, not the GPU's time: no frame timing is reported.

Not verified: the interactive mouse drawing, the keys, the Reynolds
changes in the window, the speed and pressure views on screen (the
pressure view is only compiled, the speed view only compiled and
run through the same kernel as the vorticity). Since the step is the
same code in the window and the headless run, the stability results
apply to the window, but the controls were never exercised.

## Files

- `main.vl`: the CLI, the headless checks, the window loop, the keys.
- `lattice.vl`: the D2Q9 constants, the equilibrium, the initial
  state, the disks and strokes of the mask, the Strouhal estimator,
  and the tests.
- `shaders.vl`: the WGSL: collide, stream, dye, sample, and the picture.
- `sim.vl`: the buffers, the pipelines, the bind groups, a step, the mass
  sum, the picture, and the PPM snapshot.
- `shot.png`, `vorticity.png`: the headless pictures described above.
