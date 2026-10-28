# GPU examples

Programs that compute and draw on the GPU with `std::gpu` (WGSL compute
and render pipelines, Metal on macOS) in a `std::window` window. Each
has a headless mode (`RawSurface::Headless`, no display needed) that
checks its own results, run by `tests/examples/*.test` on a Mac
(`// REQUIRES: metal`). Each builds with the plain command, in its
folder: `volec main.vl -o NAME` (`std::gpu` and `std::window` name the
frameworks they link).

| example | what it shows |
|---|---|
| [fluid2d](fluid2d/) | Stable Fluids in real time: a 1280×720 MAC grid, advection, vorticity confinement and a 40-iteration Jacobi projection a step, dye lit as a height field with glow; a compact overlay drawn by the render shader from a bitmap font; a headless divergence and dye check |
| [galaxy](galaxy/) | an N-body galaxy: a direct O(n²) compute kernel over ping-pong storage buffers, camera-facing billboards with no vertex buffers, a headless check against a CPU reference |
| [life](life/) | a massive Game of Life (4096×4096): draw, erase, pan and zoom; a torus, age-coloured cells, a check against a CPU reference and a benchmark |
| [pathtrace](pathtrace/) | an interactive path-tracing laboratory: PBR materials, refraction, area lights, GI, volumetric fog, depth of field, diagnostics and benchmarks |
| [voxel](voxel/) | a streaming procedural voxel world: GPU terrain generation, prefix-scan meshing, biomes, caves, water, vegetation, free-fly controls and sculpting |
| [galaga](galaga/) | the neural-galaga agent in a window, ported from Rust: the game, the observation encoder and the pretrained actor-critic, checked hash for hash |

New to vole? `volec guide gpu` and `volec guide window` cover the APIs.
