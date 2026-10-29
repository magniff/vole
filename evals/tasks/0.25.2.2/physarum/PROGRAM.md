# physarum

A Physarum (slime mould) simulation on the GPU, in vole (std::gpu with
WGSL compute kernels, std::window for the window).

About a million agents each sense the trail map at a left, centre and
right sensor ahead of them, turn toward the strongest, move one step and
deposit on the cell they stand on. Each step the trail diffuses (a
clamped 3x3 mean mixed in) and decays (a fraction kept), and the trail
is drawn through a colour ramp from deep blue to cream.

Files:
- `main.vl`: the command line, the headless checks, the window loop, the keys, tests.
- `sim.vl`: the buffers, the four compute kernels, the render pipeline, the readbacks.
- `shaders.vl`: the WGSL (one module per kernel, each with the shared uniform).

## Build and run

    volec main.vl -o physarum
    ./physarum                       # the window (960 x 540 trail, 1M agents)
    ./physarum --headless            # no window: the checks, 600 steps
    ./physarum --headless --steps 600 --every 100 --shot shot.ppm
    ./physarum --frames 120          # the window, quits after 120 frames and prints the mean frame time
    volec test main.vl               # the CPU-side tests

Options: `--agents N` (a multiple of 64, default 1048576), `--width W`
(the trail's width in cells, default 960; the height is 9/16 of it).

The GPU runs in this evaluation go through `tools/gpu-run`:

    ../tools/gpu-run --timeout 240 -- ./physarum --headless --steps 600 --every 300 --shot shot.ppm

## Controls (window)

- `1` / `2`: sensor angle down / up (0.05 rad steps)
- `3` / `4`: sensor distance down / up (1 cell)
- `5` / `6`: turn speed down / up (0.02 rad)
- `7` / `8`: decay up / down (7 decays the trail faster; keep = 0.92 by default)
- `9` / `0`: diffusion down / up
- left mouse button held: adds food to the trail under the pointer
- right mouse button held: repels the agents from the pointer
- space: pause the simulation; `r`: reset the agents and the trail
- `q` or Escape: quit

The current settings are printed on the terminal when a setting key is pressed.

## Headless output

`./physarum --headless --steps 600 --every 300 --shot shot.ppm` prints
the settings, a line per check (the trail's total, the total predicted
from the previous check, and their relative error), the agents outside
the trail, the steady state, the time per step, and two verdicts. The
exit status is 0 when both verdicts are ok.

The two verdicts:
- **agents stay inside**: every agent's position is finite and within [0, W] x [0, H].
- **trail follows keep * (total + deposits)**: the trail's total after
  each step is what is kept of the total plus the deposits of that
  step. The diffusion is a mean over a 3x3 neighbourhood clamped at the
  edges, which moves mass without losing any, so the total is exactly
  predictable. The check predicts the total across each interval of
  steps from the previous measured value.

## What was verified, and how

Commands and results (run from this folder):

- `volec main.vl -o physarum`: ok, built.
- `volec test main.vl`: 5 passed (-O0 and -O2 agree). Tests: the total
  levels off at keep * deposits / (1 - keep); a step keeps what it says;
  `pack` puts each setting in its word; `deposit_units` rounds like the
  shader; the clamp stays in its range.
- `gpu-run -- ./physarum --headless --agents 65536 --steps 200 --every 50`:
  both verdicts ok; the total's error at each check about 5e-8.
- `gpu-run -- ./physarum --headless --steps 600 --every 300 --shot shot.ppm`:
  1,048,576 agents on a 960 x 540 trail, 600 steps. Both verdicts ok.
  The trail's total is 2402304.7 against the steady state 2402304.5
  (0.0000% off). 0 agents outside. About 0.53 ms a step (with two
  readbacks for the checks). `shot.png` is the picture after 600 steps
  (converted with `tools/ppm2png.py`); it shows the branching networks
  a Physarum run should form.
- `gpu-run --timeout 60 -- ./physarum --frames 120`: the window opened,
  ran 120 frames and quit by itself. The window reported that it was
  occluded or the display asleep, so its frame time (101 ms, 9.8 fps) is
  the display's pacing, not the simulation's cost.

Not verified: the mouse (food and repel) and the keys were written and
compile, but I did not drive them with real input, so their behaviour is
untested. The mouse-to-trail mapping (window pixels to cells) follows
the same pattern as fluid2d but was not exercised.
