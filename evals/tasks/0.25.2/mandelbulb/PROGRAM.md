# mandelbulb

A Mandelbulb and a Mandelbox, raymarched in one WGSL fragment shader on
std::gpu (Metal here), in a std::window window, in vole 0.25.2.

- `main.vl`: the command line, the window's loop, the headless renders.
- `scene.vl`: the camera, the knobs, the keys, the fly-through (CPU side),
  and the unit tests. It also holds sin, cos and sqrt, since std has no
  math module yet.
- `shader.vl`: the WGSL, as a string constant (std has no `include_str`).
- `render.vl`: the pipeline, its uniform buffer, frames and read-backs.
- `ppm.vl`: PPM output, and the brightness statistics the checks use.

## Build and run

```sh
volec main.vl -o mandelbulb          # from this folder
volec test main.vl                   # the CPU-side tests (9)
./mandelbulb                         # the window; quits with Escape
./mandelbulb --frames 120            # the window, quits after 120 frames, prints the mean
```

Headless (run GPU programs through the lock):

```sh
../tools/gpu-run --timeout 60 -- ./mandelbulb --headless            # view 0, 320x180, timings
../tools/gpu-run --timeout 60 -- ./mandelbulb --headless --check    # views 0 to 2 with verdicts
../tools/gpu-run --timeout 60 -- ./mandelbulb --headless --fractal box --view 1 --width 640 --height 360 --shot shot.ppm
python3 ../tools/ppm2png.py shot.ppm shot.png
```

Options: `--fractal bulb|box`, `--power X` (Mandelbulb, 2 to 12, default 8),
`--scale X` (Mandelbox, -3 to 4, default 2.3), `--no-shadows`, `--no-ao`,
`--view 0|1|2`, `--width`, `--height`, `--frames N` (headless: frames timed per
view; window: quit after N frames), `--shot FILE.ppm`.

## Controls

| keys | what |
|---|---|
| left mouse drag | look around |
| W A S D | fly forward, left, back, right (in the view's direction) |
| Q / E | down / up |
| Shift | four times faster |
| arrows | turn left/right, pitch up/down |
| `-` / `=` | flight speed down / up |
| P | fly-through on or off (on at the start: the camera circles the fractal) |
| M | switch between the Mandelbulb and the Mandelbox |
| `[` / `]` | the live knob: the Mandelbulb's power (step 0.25), or the Mandelbox's scale (step 0.05) |
| L | soft shadows on or off |
| O | ambient occlusion on or off |
| R | back to view 0 |
| Escape | quit |

The window's title shows the fractal, its knob and the frame rate.

## What it does

- The distance estimate of the Mandelbulb (power `n`, 10 iterations) and
  of the Mandelbox (box fold, sphere fold, scale, 14 iterations).
- Sphere tracing with a step of 0.9 times the estimate (0.6 for the
  Mandelbox, whose estimate is looser), up to 220 steps and distance 30.
- Normals by the tetrahedron technique (four estimates), one directional
  light, soft shadows (`min(8h/t)` along the light), ambient occlusion from
  five samples along the normal, fog, and a palette driven by an orbit trap.

## What was verified and how

- `volec test main.vl`: 9 passed (sin/cos/sqrt against known values; the
  camera basis is orthonormal over a sweep of yaws and pitches; the
  preset views look at the origin from the stated distance; the knobs stay
  in range; the WASD move is along the view; a drag turns the camera by the
  dragged amount; P turns the fly-through on; the uniform block is six
  vec4s; the PPM statistics of a flat and a split picture).
- `--headless --check` (through gpu-run): all three views of both fractals
  are neither black nor flat (mean luma 0.16 to 0.29, spread 0.06 to 0.16),
  and two renders of one view are byte-identical. Power 3.5 passes too.
- Pictures: `bulb0.png`-style shots were read and looked at (the Mandelbulb
  is recognisable; the Mandelbox is a close-up of the fold structure).
- A windowed run with `--frames 120` through gpu-run quits by itself:
  120 frames at 2560 x 1440 pixels, 13.6 ms a frame (about 74 fps).
- Not verified: the mouse and the keys in a live window (they are exercised
  only by the CPU tests), and the look of the fly-through over a long time.
