# mandelbulb

An interactive Mandelbulb explorer: a ray-marched, distance-estimated 3D
fractal on the GPU, with soft shadows, ambient occlusion, orbit-trap
materials, four palettes and a dynamic-resolution governor that targets
**120 fps** without changing the camera or the fractal.

```sh
volec examples/gpu/mandelbulb/main.vl -o mandelbulb
./mandelbulb
```

On a headless machine the same fragment shader runs without a window:

```sh
./mandelbulb --headless --size 640x400 --frames 2 --out bulb.ppm
./mandelbulb --headless --power 5 --palette 1 --size 640x400 --out lagoon.ppm
./mandelbulb --headless --power 16 --palette 3 --steps 192 --size 1920x1080 --frames 60
./mandelbulb --headless --scale 0.5 --size 640x400 --out half-resolution.ppm
```

## Controls

| input | action |
|---|---|
| drag / arrow keys | orbit the fractal |
| scroll | zoom (distance 1.35 to 16) |
| `[` / `]` | decrease / increase power, 2 through 16 |
| `-` / `=` | decrease / increase march steps; manual quality at 100% scale |
| `0` | toggle the dynamic-resolution governor |
| `c` | cycle ember, lagoon, orchid and ivory palettes |
| `s` | toggle soft shadows |
| `a` | toggle ambient occlusion |
| space | pause / resume the slow automatic rotation |
| `,` / `.` | slower / faster automatic rotation |
| `r` | restore full resolution, default camera and quality |
| `f` | fullscreen |
| `q` / Esc | quit |

The title bar shows presented FPS, recent GPU cost, power, march steps,
palette, camera distance and the current film resolution. Governor changes
also log one line to stderr.

## Rendering

`mandelbulb.wgsl` draws a full-screen triangle into an offscreen film;
`display.wgsl` samples that film into the window with a bilinear upscale.
There is no vertex buffer, mesh, acceleration structure or interactive
readback. `render.vl` owns both pipelines, the film texture and a 112-byte
camera/quality uniform. Changing resolution replaces only the film and its
bind group, not the pipelines.

The distance estimator is the standard Mandelbulb recurrence in spherical
coordinates. Its speed comes from work avoided, not from approximating the
fractal:

- **Bounding sphere first:** a ray enters and exits a radius-1.2 sphere
  before marching, so empty pixels cost one sphere intersection.
- **Integer powers:** `r^p` and `r^(p-1)` use three or four squarings
  instead of `pow` and its exp/log pair.
- **Depth-scaled epsilon:** the hit threshold follows the pixel footprint
  at the current depth, so distant surfaces do not waste steps on invisible
  detail. The march is capped at 256 steps and uses a 0.85 step factor.
- **Four-tap normals, bounded extras:** the normal costs four distance
  evaluations, soft shadows at most 20, ambient occlusion four. Both extras
  can be switched off.
- **Dynamic resolution:** the film scales from 100% down to 25%, from full
  native detail to a soft upscale. Below that, the governor lowers march
  steps to 48, then shadows and AO if the GPU still cannot keep up.

### Holding 120 fps

Presentation is uncapped, because a vsync interval cannot measure shader
cost. Each frame the interactive path submits its work, waits for the GPU,
and times exactly that work. This also prevents queued frames from being
mistaken for an expensive scene. If a frame is faster than 8 ms it is paced
to the 120 fps target rather than allowed to sprint ahead.

The governor is deliberately asymmetric:

- over 8.2 ms, resolution falls quickly, using the square root of the cost
  ratio (fill rate is approximately quadratic in scale);
- below 5.6 ms for two whole seconds, it recovers only 1% resolution or two
  march steps, never a quality seesaw.

So zooming in drops resolution until the GPU is back inside budget, and it
stays there instead of oscillating between sharp and blurry frames. `r`
restores full quality; `0` disables or re-enables the governor; `-` and `=`
choose a manual march budget at 100% resolution. No governor can guarantee
a rate on every GPU and every view, but on the development machine the hard
cases tested hold the target rather than collapsing under close zoom.

Color comes from an orbit trap, direct light with soft visibility,
hemisphere and ambient terms, a rim light and a highlight. Missed rays get
the sky gradient plus a small silhouette aura. Output goes through an ACES
curve and gamma 2.2.

## Headless verification

`check.vl` renders deterministic 100%-scale frames by default through
`RawSurface::Headless`, reads them back, and requires:

- an image with real contour detail, useful dynamic range and a nonblank
  mean, which catches a blank sky, broken distance estimate or NaNs;
- two identical frames that agree byte for byte, which catches accidental
  time-dependent input or uninitialized state.

`--scale` also exercises fractional films and the upscale pass without any
timing dependence. The program prints wall time per frame (including a
full readback each frame) and can write a PPM. Cases live in
`tests/examples/gpu-mandelbulb*.test`; the scripted case drives the native
window's own event loop, changes palette and shadows, orbits the camera and
compares a cropped PPM.

## Performance

Measured on an Apple M5 with Metal, default power 8 and 112 march steps,
including a full readback every frame: **about 10 ms/frame at 1100×720 and
19 ms/frame at 1920×1080**. The interactive governor targets 8 ms plus
presentation overhead. At closest zoom and power 16 it settles at a smaller
film and holds there instead of missing the target or cycling resolutions.

## Files

| file | role |
|---|---|
| [main.vl](main.vl) | CLI, native window, camera, input and 120 fps governor |
| [render.vl](render.vl) | offscreen film, uniform packing and both render passes |
| [mandelbulb.wgsl](mandelbulb.wgsl) | distance estimator, ray marcher and shading |
| [display.wgsl](display.wgsl) | bilinear film-to-window upscale |
| [check.vl](check.vl) | headless readback, image checks, PPM and timing |
