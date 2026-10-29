# mandelbulb

A Mandelbulb and a Mandelbox, raymarched on the GPU in vole (std::gpu, WGSL)
and shown in a window (std::window), with a smooth fly camera and a power
parameter you change live. The headless mode renders fixed views to PPM and
prints timings and checks.

Files: `main.vl` (the GPU side, the window, the headless mode, the CLI),
`camera.vl` (pose, easing camera, views, the uniform block, tests),
`shader.vl` (the WGSL: distance estimators, the march, shadows, AO, shading,
and a blit that stretches the scene texture over the window).

## Build and run

    volec main.vl -o mandelbulb
    ./mandelbulb                       # the window
    ./mandelbulb --headless            # the four fixed views: timings and checks
    ./mandelbulb --headless --view 1 --shot v1.ppm

Headless options: `--view K` (0 to 3), `--width`, `--height` (default 640x360),
`--frames N` (timed frames per view, after one warm-up frame), `--power P`,
`--shot FILE.ppm` (needs `--view`), `--no-shadows`, `--no-ao`. Exit status 0 when
every view's picture has spread (not flat).

Window options: `--kind bulb|box`, `--power P`, `--view K` (start pose),
`--scale N` (the scene is rendered at 1/N of the frame's pixels and stretched,
default 2), `--frames N` (quit after N frames and print the mean frame time).

Tests: `volec test main.vl`.

## Controls (window)

| keys | what |
|---|---|
| W A S D | fly forward, left, back, right (relative to the view) |
| Q / E | down / up |
| Shift | three times faster |
| mouse drag (left button) | look around |
| Up / Down | the Mandelbulb's power (2 to 16), or the Mandelbox scale (-3 to -1) |
| 1 / 2 | the Mandelbulb / the Mandelbox |
| + / - | the estimate's iterations (detail, 4 to 40) |
| X | soft shadows on or off |
| G | ambient occlusion on or off |
| O | the automatic fly-through on or off |
| Space | pause the animated colour clock |
| R | back to the front view |
| Esc | quit |

The window title shows the fractal, power, scale, steps and effects.

## What it does

- One full-screen fragment pass per frame. Each ray is clipped to a bounding
  sphere, then sphere-traced on the distance estimate (step factor 0.8).
- Mandelbulb: Quilez's distance estimate with the orbit trap (closest approach
  to the origin) for colour. Mandelbox: box fold, sphere fold, scale and shift.
- Soft shadows (the closest approach to the surface, relative to distance) and
  five-sample ambient occlusion, both switchable.
- Camera: keys and the mouse set a goal pose; the camera eases to it
  exponentially (about 8 per second), so motion is smooth at any frame rate.

## What was verified, and how

- `volec test main.vl`: 4 tests pass (camera basis orthonormal, forward
  direction at yaw 0, pack puts power and kind in the right words, the ease
  reaches its goal). Both -O0 and -O2 agree.
- Headless renders, all four views, through `tools/gpu-run`. The check in each
  line is the luminance mean and spread and the number of distinct colours
  (quantised); a flat picture fails. Output in `shots/headless_640x360.txt`.
  Pictures were read as PNG: `shots/view0.png` to `view3.png` (the PPMs beside
  them), and `shots/power12.png` (the power 4 and 8 PPMs are in `shots/`).
- Power has a visible effect: `shots/power12.png` versus the power 8 view.
- Windowed: a 60-frame run and a 120-frame run each quit by themselves with
  exit 0 (through gpu-run). The window was not shown (the run came from a
  background shell), so its frame time is the 10 fps occluded timer, not a
  measurement. The keys and the mouse were not exercised by hand.

## Timings (gpu-run, 20 frames after a warm-up, the machine's load about 3)

| view | 640 x 360 | 960 x 600 |
|---|---|---|
| 0 Mandelbulb front | 1.6 ms | 3.2 ms |
| 1 Mandelbulb close | 2.7 ms | 4.9 ms |
| 2 Mandelbulb above | 1.9 ms | 3.4 ms |
| 3 Mandelbox far | 2.6 ms | 5.2 ms |

Earlier runs of the same views measured 15 to 20 ms at 640 x 360 while the
machine's load was high (15-minute load average near 10). Those numbers are
not used here; the timings above were repeated and stable.

## Known limits

- The Mandelbulb's estimate is not a true bound, so thin structures can show
  faint speckle at grazing angles; the step factor 0.8 trades speed for that.
- The window's frame time was not measured on a visible window (see above).
- The Mandelbox's bounding sphere (radius 5) is a guess that fits the views.
