# voxel

A deterministic, streaming voxel world written in Vole. Terrain density,
parallel mesh offsets, vertices, water and vegetation are generated on the GPU;
the application streams a bounded set of chunks around a free-fly camera and
presents depth-tested geometry through Vole's native `std::window` window.

## Build and run

From the repository root:

```sh
target/volec -O2 examples/gpu/voxel/main.vl -o voxel
./voxel
./voxel --seed 42
```

On macOS the current backend is Metal. No assets or additional link flags are
needed. The title reports CPU frame time, visible/loaded chunks, draw count, an
explicitly estimated triangle count, seed and camera position.

## Controls

| input | action |
|---|---|
| WASD | fly forward/back and strafe |
| Space / Shift | fly up / down |
| left-drag | look around (absolute mouse events; no pointer capture) |
| scroll | adjust movement speed |
| left / right arrow | cycle sun direction |
| `e` | toggle sculpting mode |
| sculpt + left / right click | remove / add density ahead of the camera |
| sculpt + scroll | change brush radius |
| F3 | cycle chunk boundaries, normals, biome IDs, height and edge debug views |
| `f` | toggle triangle-edge debug view |
| `r` | regenerate the current seed, replaying session edits |
| `n` | generate the next seed |
| `q` / Esc | quit |

The sculpt preview is a magenta spherical band on the affected terrain.
`std::window` currently has no relative-mouse/capture API, so looking uses a
predictable drag rather than inventing a second input path.

## Procedural world

- Chunks contain **32×32×48 voxels**. The normal working set is a 7×7 chunk
  square (49 chunks), with one-chunk unload hysteresis and up to four new chunks
  generated per frame. There is no hard world boundary and no whole-world
  allocation.
- Height combines domain-warped multi-octave value noise, broad/detail fields
  and ridged mountain noise. Moisture and elevation select plains, forest,
  sand, rock and snow. These fields affect color and vegetation placement.
- A continuous three-dimensional cave field subtracts tunnels and cavities
  from the height density. Neighbor voxels outside a chunk are evaluated by
  world coordinate, producing identical boundary density and no chunk seams.
- Lakes occupy low terrain at the water level. Water has depth-dependent color,
  animated surface displacement/ripples, Fresnel-like environment reflection
  and alpha blending with depth writes disabled.
- Trees and grass use deterministic world-coordinate candidates, slope/biome
  checks and stable size/type variation. Crossed procedural silhouettes are
  GPU-instanced, wind-animated and thinned by distance. No global RNG stream or
  load-order-dependent placement is used.

## GPU architecture

1. `terrain` computes one height per x/z column and writes its 48 density values.
   Session sculpts are replayed into this world-space density.
2. `mesh` processes 192 tiles of 256 voxels per chunk. A Hillis–Steele
   **workgroup parallel prefix scan** assigns deterministic face offsets; no
   per-voxel data returns to the CPU.
3. A second parallel sweep emits only exposed faces. Terrain uses flat voxel
   normals, biome materials and an ambient-occlusion approximation. The same
   pass emits water and instanced vegetation records.
4. Native rendering uses depth attachments and CPU frustum filtering, followed
   by opaque vegetation and alpha-blended water. The sun, fog and wind uniforms
   update without rebuilding terrain.

`std::gpu` has no indirect-draw API. Each chunk therefore keeps its generated
vertex count in GPU metadata and issues a bounded draw; vertex invocations past
that count produce degenerate positions. There is no per-frame count or image
readback. Capacities are 12,288 terrain faces, 6,144 water vertices and 256
plants per chunk. Terrain overflow is clamped and flagged in metadata rather
than corrupting memory; extreme edited terrain can exceed the fixed capacity.

The representation is deliberately exposed-face voxel geometry rather than
greedy meshing or marching cubes: it preserves the block visual identity and
makes density sculpting straightforward. Distant terrain LOD, shadow maps,
persistent save files and mouse capture are not included. Vegetation has
distance LOD; terrain uses chunk/frustum filtering.

## Editing and determinism

Up to 1024 session edits are stored separately from chunks in a shared GPU
buffer. A sculpt invalidates intersecting chunks plus their boundary neighbors.
Unloading and reloading replays the same edit list over deterministic base
terrain, preserving modifications without saving the whole world.

Given one seed and world coordinate, base density and object placement do not
depend on chunk loading order. Time affects only water and vegetation motion.
The headless test performs a carve, removes the chunk, reloads it through the
normal streaming path and checks the regenerated mesh count.

## Verification

```sh
target/volec test examples/gpu/voxel/main.vl
./voxel --headless --size 320x200 --out voxel.ppm
```

The seven Vole tests cover negative chunk conversion, deterministic procedural
fields, biome selection, occupancy/neighbor face rules, prefix offsets,
load-order-independent placement, camera movement and replayable sculpt math.
The GPU smoke test uses the real compute/render pipelines and covers nontrivial
pixels, deterministic mesh regeneration and edit persistence across reload.

## Benchmark

```sh
./voxel --benchmark --size 1280x720 --frames 240
```

Initialization, streamed generation and offscreen steady-state rendering are
measured separately. Rendering includes one final synchronization, with no
presentation pacing or per-frame readback. These are CPU wall measurements,
not GPU timestamp claims; `std::gpu` exposes no timestamp queries.

Measured on **Apple M5 / Metal**, seed 1, 1280×720, 240 frames:

- 40 additional chunks (1,966,080 voxels) generated in **45.30 ms**,
  **43.4 Mvoxels/s**.
- **1.371 ms/frame**, **729.6 fps** offscreen.
- 49 loaded chunks, 35 visible, 105 draw calls and **419,662** generated terrain
  triangles in the measured world.

The native window is presentation-limited rather than expected to reach the
offscreen FPS. Run the command for local results.

## Files

| file | role |
|---|---|
| [main.vl](main.vl) | native window, event loop, free-fly and sculpt controls |
| [camera.vl](camera.vl) | camera basis, movement and tests |
| [world.vl](world.vl) | bounded streaming, GPU resources, edit history and procedural tests |
| [shaders.vl](shaders.vl) | WGSL noise, caves, scan meshing, water, vegetation and rendering |
| [render.vl](render.vl) | camera uniforms, depth target, frustum filtering and native presentation |
| [check.vl](check.vl) | real GPU smoke tests, PPM output and offscreen benchmarks |
| [TOOLING.md](TOOLING.md) | compiler/shader errors and verified API limitations encountered |
