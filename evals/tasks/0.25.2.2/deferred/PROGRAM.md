# deferred

A deferred renderer on std::gpu (WGSL on Metal) and std::window.

- G-buffer pass: the scene (a checkered floor, a 7 x 7 grid of boxes of
  seeded heights, three spheres) into three colour targets (albedo
  Rgba8Unorm, view-space normal Rgba16Float, linear depth R32Float) with
  a Depth32Float buffer for the visibility test.
- Light culling (compute): one 16 x 16 workgroup per tile. The tile's
  depth range is an atomic min/max over its pixels; its four side planes
  come from its corner rays. Each light (512 by default, 256 to 4096) is
  tested against both; survivors go into a per-tile list (up to 127).
- Lighting: a fullscreen pass; each pixel walks its tile's list.
- Tone mapping (Reinhard + gamma) to the frame, or to a G-buffer view.

## Run

    volec main.vl -o deferred          # in this folder
    ./deferred                         # the window (std::window), 512 moving lights
    ./deferred --lights 1024           # more lights (256 to 4096)
    ./deferred --headless --frames 600 --size 960x600 \
        --shot final.ppm --views out   # time frames; write final + G-buffer views
    volec test main.vl                 # the CPU-side #[test]s (math, scene)

Headless prints the frame time (wall clock over N frames submitted back
to back, ended by a wait for the GPU). `--views PREFIX` writes
PREFIX-final.ppm, -albedo, -normal, -depth and -lights (the tile heat
map: how many lights each tile kept). Convert with
`tools/ppm2png.py` to look at them.

## Controls (window)

| key | view |
|---|---|
| 0 | the lit frame |
| 1 | albedo |
| 2 | normal |
| 3 | depth |
| 4 | lights kept per tile (heat: blue none, red many) |
| 1-4 again | back to the frame |
| space | pause the lights |
| q | quit |

## Verified

- `volec test main.vl`: 7 tests pass at -O0 and -O2 (look_at maps the eye to
  the origin and the target onto -z; the perspective edge ray is at NDC 1;
  the floor is 400 vertices / 600 indices; scene indices stay in range; hsv
  primaries; rnd in range; lights stay near the floor with valid colours).
- Headless run: see the numbers in the report below; the images were
  read back and checked by eye (albedo: flat colours of the boxes and
  checks; depth: near is dark, sky is black; lights: sky tiles keep 0
  lights, the tiles along the boxes keep many).

## Limits

- A tile keeps at most 127 lights; beyond that the extra lights are
  dropped silently for that tile (visible as missing light on very dense
  tiles; the heat view shows it saturating).
- The window's size is fixed at open time except for resize (targets are
  rebuilt on Resize).
- The light count is fixed when the program starts.
