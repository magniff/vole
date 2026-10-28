# deferred

A deferred renderer in vole on std::gpu (WGSL, on Metal) and std::window.
Generated scene (a 12 x 12 checkered floor, 10 cubes, 8 spheres), a G-buffer
pass into three colour targets (albedo, view-space normal, linear depth) with
a hardware depth test, 512 orbiting coloured point lights culled per 16 x 16
pixel tile in a compute pass, a lighting compute pass that shades every pixel
from its tile's lights (plus a sun and ambient), and an ACES tone map in a
render pass. Pixels with no geometry get a sky gradient.

## Build and run

```sh
volec main.vl -o deferred          # no C, no build script, no unsafe
volec test main.vl                 # the CPU-side #[test]s (scene.vl)
./deferred                         # the window (1280 x 720 points; Esc or q quits)
./deferred --frames 120            # the window: 120 frames, prints the mean, then quits
./deferred --headless              # no window: 120 frames timed, tile stats
./deferred --headless --shot shot.ppm
                                   # also shot.ppm (final), shot-albedo.ppm,
                                   # shot-normal.ppm, shot-depth.ppm
```

Under the eval's machine rules, GPU programs run as
`tools/gpu-run -- ./deferred ...`.

## Controls

| key | action |
|---|---|
| 1 / 2 / 3 / 4 | final picture / albedo / normal / depth (G-buffer) |
| v | next view (cycles final, albedo, normal, depth) |
| space | pause / resume the lights |
| q or Esc | quit |

## Files

- `main.vl`: the command line, the window loop, the headless run.
- `render.vl`: the `Renderer`: buffers, textures, four pipelines, bind groups,
  the frame's encoding (`upload`, `scene`, `composite`, `record`, `shot`,
  `tile_stats`).
- `scene.vl`: the meshes (floor, cubes, UV spheres), the seeded lights'
  orbits, the column-major matrices, and the `#[test]`s.
- `shaders.vl`: the WGSL, one module per pass (G-buffer, cull, light,
  composite); the frame uniform is shared.

## What was verified, and how

- `volec main.vl -o deferred` builds; `volec test main.vl`: 5 passed (-O0 and
  -O2 agree): the RNG range, the scene's vertex and index counts, the look-at
  point projecting to the screen centre, every light in front of the camera,
  light colours in range.
- Headless, through gpu-run (`--headless --frames 120 --shot shot.ppm`):
  0.913 ms a frame at 1280 x 720 with 512 lights (mean of 120 frames after 10
  warm-up frames; the GPU's time, submitted frames back to back, one readback
  at the end). The tile statistics: at most 158 lights offered to one tile
  (cap 256), no tile over the cap. Result in `headless.txt`.
- The pictures `shot.png`, `shot-albedo.png`, `shot-normal.png`,
  `shot-depth.png` were read back and looked at: the lit scene with coloured
  light falloff, the flat albedo, the view-space normals (the floor is green:
  up in view space), and the depth (near white, dark at about 20 units).
- Windowed: `./deferred --frames 120 --shot win.ppm` through gpu-run quits by
  itself after 120 frames (`windowed.txt`; the frame was 2560 x 1440, the
  Retina size; the PPM was converted and then removed). The window was not shown
  (the display was asleep or the window occluded), so its frame time is the
  100 ms timer's, not the GPU's, and is not reported as a result.

Not verified: the key handling (views and pause were not exercised with key
input); the culling against a brute-force reference (only the tile counts and
the lit picture); the look of the windowed mode on a visible display.

## Notes

- The HDR target is `rgba32float`: this release accepts only rgba8unorm,
  rgba32float, r32float, r32uint, r32sint and rgba32uint as storage textures
  (`rgba16float` fails at run time with `wgsl.unsupported`).
- A tile keeps 256 lights; more are dropped (the headless run reports them).
- The window's size is fixed at the start: a resize is not handled.
