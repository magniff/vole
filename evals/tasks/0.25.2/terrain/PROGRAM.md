# terrain

A procedural terrain fly-over in vole, on std::gpu (WGSL on Metal) and
std::window.

- The heightmap is six octaves of value noise, computed by a compute
  shader into a 257 x 257 storage buffer. The vertex shader reads that
  buffer, so there is no vertex buffer; normals come from the neighbours.
- The mesh is 8 x 8 tiles of 32 x 32 quads, each drawn at one of four
  levels of detail (steps 1, 2, 4, 8) chosen by the tile's distance to
  the eye. Each tile at each level is one range of one index buffer.
  Skirts (the tile's edges dropped 40 units) hide the cracks between
  levels.
- The sun casts shadows: a depth-only pass renders the terrain into a
  2048 x 2048 Depth32Float map (its colour target is a dummy), and the
  terrain fragment shader samples it with a 3 x 3 percentage-closer
  filter.
- Materials by height and slope: grass, rock on steep faces, snow above
  about 24 units on steep faces, sand at the shore. Fog by distance.
- Water: a sea-level square (y = 0) that reaches past the map, alpha
  blended, with a sun glint.

## Run

```
volec main.vl -o terrain
volec test main.vl                       # the CPU-side tests (5)
./terrain --headless                     # the checks, printed
./terrain --headless --shot shot0.ppm --camera 0   # one frame; camera 0, 1 or 2
python3 ../tools/ppm2png.py shot0.ppm shot0.png
./terrain                                # the fly-over in a window
./terrain --frames 120                   # the same, quitting after 120 frames
```

On this machine, run the GPU programs through
`../tools/gpu-run --timeout 60 -- ...`.

## Controls (window)

- Space: pause or resume the fly-over.
- Closing the window quits.

The fly-over is a smooth path through four waypoints, one segment each
12 seconds long at 60 frames a second.

## What the headless run prints

- The noise: the number of heights, their min, max and mean, and whether
  they lie in [0, 1] with a spread over 0.3.
- The levels of detail: how many tiles are at each level for the chosen
  camera, and the triangles they draw; a check that at least two levels
  are in use.
- The shadows: the overview frame rendered with the shadow map on and
  off; the pixels darker by 10% or more, and a check that some are and
  not all.

The exit status is 0 when all checks pass, 1 otherwise.

## What was verified, and how

- `volec test main.vl`: 5 tests pass at -O0 and -O2. They cover the
  Newton square root, the look-at matrix, the orthographic projection,
  the triangle count of every (tile, level) range against the formula
  2q^2 + 8q, and the level-of-detail thresholds.
- `volec main.vl -o terrain` builds; `volec check` is clean.
- `./terrain --headless` on all three cameras, through gpu-run. The
  noise range was 0.149 to 0.835 (mean 0.490). The overview camera uses
  levels 2 and 3; camera 1 (close, on the sun side) uses all four; the
  shadow check reports 6.3% of the
  overview frame in shadow. The rendered shots were looked at: the
  overview shows the sea, grass, rock, snow, fog and the terrain's shadow;
  camera 2 shows a lit mountain face.
- The windowed mode did NOT run to completion in this environment: three
  attempts under gpu-run (`--frames 1`, and `--frames 120` twice) were
  killed by the timeout without printing anything. The headless path
  uses the same render function. The window path is not verified.

## Known limits

- The windowed run is unverified (see above).
- No frustum culling: every tile is drawn at its level, in both passes.
- The shadow map covers a fixed 380 x 380 box around the terrain centre.
- The terrain is not stitched: skirts hide cracks, but a high-contrast
  edge between two levels can still show a step at the horizon.
