# terrain

A procedural terrain fly-over in vole, on std::gpu and std::window.

- A 257 x 257 heightmap of fractal value noise (6 octaves, ridged
  detail), made by a compute kernel on the GPU.
- The terrain is a 16 x 16 grid of blocks of 16 x 16 cells. Each block is
  drawn at a step of 1, 2, 4 or 8 cells by its distance from the eye. The
  vertices are never stored: the vertex shader reads each grid point's
  height from the heightmap and computes its normal from the neighbours.
- A sun (direction fixed) with a 1024 x 1024 shadow map: a depth-only
  pass from the sun's orthographic view, read back with a 3 x 3 PCF.
- Fog (exponential, to the sky colour) and materials by height and slope:
  grass, rock on steep faces, snow on high ground that is not steep, sand
  at the shore.
- Water at sea level (0.30 of the height range), alpha-blended after the
  terrain, with a Fresnel tint and a sun glint.

## Run

```sh
volec main.vl -o terrain          # builds with std only
./terrain                         # the fly-over in a window (a circle round the island)
./terrain --frames 120            # the same, quitting after 120 frames
./terrain --headless              # no window: prints the checks, exits 0 when all pass
./terrain --headless --cam 2 --shot shot2.ppm
                                  # camera 1, 2 or 3, written as a PPM (convert with tools/ppm2png.py)
volec test main.vl                # the #[test]s (math, LOD, index lists): 7 pass
```

GPU programs are run through `evals/tasks/0.25.2.1/tools/gpu-run`.

## Controls

None. The fly-over is automatic; closing the window quits. The fixed
cameras (`--cam 1..3`) are headless only.

## Files

- `main.vl`: the arguments, the headless checks and shots, the window loop.
- `scene.vl`: the GPU objects, the cameras, a frame's passes.
- `shaders.vl`: the WGSL: the noise kernel, the terrain module (shadow
  pass, lit terrain), the water module.
- `terrain.vl`: the grid's constants, the LOD choice, the index lists.
- `math.vl`: vectors and matrices (column-major, depth 0..1), with tests.

## What was verified, and how

Headless, on the GPU (through gpu-run), `./terrain --headless --cam 2 --shot shot2.ppm`:

- Noise range: min 0.000, max 1.000, mean 0.557, 9.9% under sea level.
  The check requires range within [0, 1], spread over 0.5, and 5% to 60%
  under sea level.
- LOD triangle counts per camera (each total is the sum over blocks of
  (16/step)^2 * 2 triangles, and the check compares each level with its
  block count):
  - camera 1: 22 blocks at step 1, 47 at 2, 118 at 4, 69 at 8; 21608 triangles.
  - camera 2: 0 / 4 / 53 / 199; 3800 triangles.
  - camera 3: 26 / 56 / 126 / 48; 24896 triangles.
- Shadows: the same view rendered with the shadow map on and off; the
  pixels it darkens are 2.5% (camera 1), 2.0% (camera 2), 5.9% (camera 3).
- The shots (`shot1.png`, `shot2.png`, `shot3.png`, from the PPMs) were
  looked at: camera 2 shows the island, the snow, the sea and the beach
  edge; camera 1 shows the valley ridges in grass, rock and snow with fog;
  camera 3 is a steep cliff above the water. The shadow bias was raised
  from 0.0008 to 0.0025 after acne (banding) on camera 3's steep rock.
- `volec test main.vl`: 7 tests pass at -O0 and -O2 (matrix maths, LOD
  thresholds, index template sizes, index range and triangle count).
- Windowed: `./terrain --frames 120` through gpu-run ran and exited 0. The
  display was asleep or occluded, so the frames came from the window's
  timer and nothing was seen on screen; frame times are not reported.

## Known limits

- Cracks: neighbouring blocks at different steps leave small seams where
  the terrain edges do not match (no skirts or stitching).
- No frustum culling: all 256 blocks are always indexed.
- The sun is fixed; the shadow box is fixed (380 world units across).
- The index list is rebuilt on the CPU and uploaded each frame (up to
  about 1.5 MB).
- Water has no shadows and no reflections of the terrain.
