# mandelbulb

A Mandelbulb and a quaternion Julia set, raymarched on the GPU by one
WGSL fragment shader (std::gpu on Metal). Distance estimation, sphere
tracing, a soft shadow, ambient occlusion, sky and fog. A smooth fly
camera and the power changed live in the window; a headless mode for
fixed views with timing and checks.

## Build and run

    volec main.vl -o mandelbulb
    ./mandelbulb                       # the window (1280 x 720 requested)
    ./mandelbulb --headless            # three fixed views, numbers, timing
    ./mandelbulb --headless --view 1 --shot v1.ppm
    volec test main.vl                 # the CPU-side tests

Windowed and headless GPU runs go through `tools/gpu-run`.

Options: `--power P` (Mandelbulb power, 2 to 12, default 8), `--julia`
(start on the Julia set), `--iters N` (estimator iterations, default 9),
`--no-shadows`, `--no-ao`, `--frames N` (window: quit after N frames and
print the mean frame time; headless: frames per timing round, default 20),
`--size N` (headless picture side, default 512), `--view K` (headless:
which view `--shot` writes), `--shot FILE.ppm`.

## Controls (window)

- drag with the left mouse button: orbit the target
- arrows: orbit by keys
- w / s: fly forward / back; a / d: strafe; q / e: down / up
- + and -: zoom in / out; r: reset the camera
- f: auto fly on / off (a slow orbit and a drift through the set)
- [ and ]: the Mandelbulb's power down / up (0.25 a press, clamped 2..12)
- j: switch between the Mandelbulb and the quaternion Julia set
- i: soft shadows on / off; o: ambient occlusion on / off
- space: pause the animation clock (Julia constant and auto fly)
- Esc: quit

The camera eases toward what the keys ask for (about 8 a second), so
motion is smooth at any frame rate.

## Files

- `main.vl`: the program: options, the window and headless loops, the
  uniform block, the views, the PPM and the checks.
- `camera.vl`: the CPU side of the camera (f64 vectors, a target, yaw,
  pitch, distance, easing) and its tests.
- `shader.vl`: the WGSL (distance fields, marcher, shading), as one
  string constant.

## What was verified and how

- `volec check` and `volec main.vl -o mandelbulb`: clean.
- `volec test main.vl`: 7 tests pass at -O0 and -O2 (camera basis
  orthonormal, eye at its distance and looking at the target, fly moves
  toward the target, pitch and zoom clamp, easing converges, power clamp,
  PPM header length).
- Headless (`--size 384 --frames 10`, through gpu-run): the three views
  render; hit shares 63.9%, 100.0%, 75.1%; brightness 0.30, 0.17, 0.33;
  shading is not flat (checked by eye on the PNGs, see below).
- Timing (through gpu-run, 1024 x 1024, view 0): 9.3 ms a frame with
  shadows and AO, 4.9 ms with both off, 8.1 ms with 6 iterations.
- Windowed: `--frames 120` through gpu-run quits itself and writes a
  2560 x 1440 frame; I looked at it and it shows the Mandelbulb lit and
  shaded. The window was occluded for part of that run (the program said
  so), so its frame time (about 100 ms) is not a measurement.
- Not verified: the keys and the mouse. The window's event path was
  compiled but I did not drive it (no interactive run was allowed), so
  the controls are untested in practice.
