# deferred

A deferred renderer in vole (std::gpu, WGSL on Metal, std::window).

- Scene: 24 cubes, 16 spheres (bobbing) and a floor, generated (the cube and
  sphere meshes are written by a compute pass), and 512 coloured point lights
  orbiting over it.
- Frame: update (compute: lights and objects move), cull (compute: one
  workgroup per 16 x 16 tile lists the lights that may touch it), three
  geometry passes into the G-buffers (albedo RGBA8, normal RGBA16F, world
  position + view depth RGBA32F), lighting (fragment, each pixel loops over
  its tile's lights), view (ACES-style tone mapping, or one G-buffer).
- std::gpu's render pass takes one color target, so the G-buffer is three
  passes over the same geometry, not one multiple-target pass.

Files: `main.vl` (modes, window loop, headless), `render.vl` (the GPU
objects and the frame), `scene.vl` (CPU data, fixed camera, unit tests),
`shaders.vl` (the WGSL).

## Build and run

    volec main.vl -o deferred
    ./deferred --headless --frames 300 --check --shot shots/shot.ppm
    ./deferred                      # the window; Escape quits
    ./deferred --frames 600         # the window, quits after 600 frames, prints ms a frame
    volec test main.vl              # the CPU-side tests (3)

Headless prints the frame time (mean wall time over N frames, after one
warm-up frame, includes encoding and waiting for the GPU), and with `--check`
the culling check. With `--shot FILE.ppm` it writes the lit frame to FILE.ppm
and the views to FILE-albedo.ppm, FILE-normal.ppm, FILE-depth.ppm. PPM to PNG:
`python3 ../../tools/ppm2png.py FILE.ppm FILE.png`.

## Controls

- 1: albedo, 2: normal, 3: view depth (near is white), 0: the lit frame.
- Escape or closing the window quits.

## What was verified and how

- `volec check` clean, `volec test main.vl`: 3 passed (the camera maps the
  eye to the origin and the origin to depth 13; the RNG is deterministic and
  in range; the record counts match the layout).
- Headless, through gpu-run: the four PPM views were rendered and inspected
  (lit frame, albedo, normal, depth all agree with the scene).
- `--check`: reads back the lights, tile lists and world positions of the
  frame and verifies that every light whose sphere contains a sampled pixel's
  position is in that pixel's tile list. Result on the final version: 0
  missed of 410988 light-pixel pairs over 64779 sampled pixels; the first
  version of the cull (a projected disc) missed 9 pairs, which is what the
  check was added to catch.
- Timing (gpu-run, uncontended): 300 frames at 1280 x 720, 512 lights, about
  1.35 ms a frame.
- NOT verified: the windowed mode. In this session `./deferred --frames 3`
  under gpu-run did not return within 30 s and printed nothing; the keys and
  the window loop are untested.
