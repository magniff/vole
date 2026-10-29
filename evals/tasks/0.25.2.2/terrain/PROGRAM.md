# terrain

A procedural terrain fly-over in vole, on std::gpu and std::window.

- The heights are seven octaves of value noise, computed by a WGSL compute
  kernel into a storage buffer (513 x 513 samples, 2 world units apart).
- The terrain is 16 x 16 chunks of 32 quads. Each chunk draws at a step of
  1, 2, 4 or 8 grid cells a quad, chosen by its distance to the eye. Every
  chunk has a skirt under its four edges, so neighbours at different steps
  leave no cracks. Vertices are not stored: a vertex is a grid sample index,
  its height is read from the buffer and its normal from the neighbours.
- The sun casts a shadow map from a depth-only pass (2048 x 2048,
  Depth32Float), sampled with a 3 x 3 comparison.
- Materials by height and slope: sand near the sea, grass, rock on steep
  slopes, snow on high flat ground. Exponential fog toward the horizon.
- The sea is a plane at height 0, drawn last with a fresnel tint and a sun
  glint. It is opaque: the terrain under it is hidden.

## Run

```sh
volec main.vl -o terrain
./terrain --headless                          # the numbers and the checks
./terrain --headless --shot shot.ppm --camera 1   # a fixed camera as PPM
python3 ../tools/ppm2png.py shot.ppm shot.png
./terrain                                     # the window: a fly-over
./terrain --frames 120                        # the window for 120 frames, then the mean
volec test main.vl                            # the CPU logic
```

`--headless` prints the heights' range and the sea fraction, the chunk
counts per step and the triangles drawn for three fixed cameras (against the
full-detail grid), the fly-over's triangles, and the shadow map's coverage.
Each has a check; the exit status is 1 if one fails. `--seed N` changes the
terrain.

## Controls (window)

- space: pause the fly-over
- q: quit

The camera flies along a fixed path at 45 units a second, 110 units up.

## What was verified and how

- `volec check main.vl`: no errors.
- `volec test main.vl`: 8 tests pass at -O0 and -O2 (matrices: identity,
  look-at, perspective depth 0 and 1, ortho box; LOD: step thresholds,
  triangle counts per step, nearest chunk at step 1, far chunks at step 8,
  chunk centres).
- `./terrain --headless` through `gpu-run`: heights min -55.8, max 88.2, mean
  3.8, 44.3% of the samples under sea level; chunk steps for camera 0:
  24/45/104/83 (1/2/4/8), 109376 triangles of 589824 at full detail; shadow
  map covered 38.3%. All checks ok.
- `shot1.png` (camera 1, final settings): grass, sand, rock on the slopes,
  shadows, a snow cap on the far peak, the sea.
- `./terrain --frames 120` through `gpu-run`: runs and quits. The frame time
  it prints (about 100 ms) is not meaningful: the window was not shown and
  the system throttled frames to 10 a second.

Not verified: the window's look on a visible display, and timings.
