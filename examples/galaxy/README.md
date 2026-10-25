# galaxy

An N-body simulation of a spinning galaxy: a pinned core, a few
thousand disk stars on near-circular orbits, computed entirely on the
GPU (one `@compute` kernel over storage buffers) and rendered into a
real window (`std::window` + `std::gpu`, Metal on macOS) as
camera-facing glowing billboards — no vertex buffers, no textures.

```sh
target/volec -O2 examples/galaxy/main.vl -o galaxy
./galaxy                       # 8192 stars
./galaxy --stars 16384         # a heavier disk
./galaxy --headless            # no display needed: the self-check
./galaxy --headless --out g.ppm --size 960x600
```

On a display with a window server the program opens a window and starts
stepping; the title bar carries the frame rate. The camera opens
perpendicular to the disk — straight down its axis, the galaxy flat in
the frame — and the drag and the arrows tilt and spin it from there.
Keys and mouse:

| input | action |
|---|---|
| drag / arrow keys | orbit the camera (yaw, pitch) |
| scroll | zoom |
| space | pause |
| `,` / `.` | slower / faster |
| `r` | a new disk (the seed rerolls) |
| `f` | fullscreen |
| `q` / Esc | quit |

## The parts

| file | what |
|---|---|
| [physics.vl](physics.vl) | the star state, the O(n²) `advance` compute shader, the seeded initial disk, the `Galaxy` that owns the buffers and steps them |
| [view.vl](view.vl) | the `vs`/`fs` shaders that draw the state, the `Sky` pipeline, the camera constants |
| [check.vl](check.vl) | `--headless`: the same steps on the GPU and on a CPU reference, one frame rendered into a headless surface, read back and checked |
| [main.vl](main.vl) | the CLI, the window, the event loop, the camera keys, the title's frame rate |

## What it shows on std::gpu

- **A compute kernel with no host loop.** One WGSL shader (a `const
  [u8]` in physics.vl, compiled by `dev.shader_wgsl`) advances every
  star: for star `i` it sums the pull of every other star, integrates
  semi-implicit Euler (`v += a·dt` then `x += v·dt`), and writes into
  *the other* buffer of a ping-pong pair — `src` is bound
  `read`, `dst` `read_write`, and `Galaxy::step` flips `cur`.
- **The renderer reads physics' buffers directly.** `sky_new` binds the
  same two `Buffer`s a render pipeline's `var<storage, read>`; no
  staging, no vertex buffers. Each star is an instance: the vertex
  shader builds its four corners from `vertex_index` and
  `instance_index` alone, projects them by hand (`k = foci/depth`),
  culls stars behind the camera by pushing them off clip space, and the
  fragment glows `exp(−k·r²)` in a hue Warm↔cool mix of the star's
  hue. Blending is `Blend::additive()`, so overlapping stars sum into
  the bright heart.
- **Uniforms are packed by hand.** Both shader uniforms are plain
  `f32` structs the host fills with `gpu::bytes_of_f32` into buffers
  sized with `dev.align_uniform`: the sim's `n/dt/g/soft/drag`, the
  view's camera (two cosines, two sines, distance, zoom, aspect, star
  radius). Window sizes come in physical pixels (`win.size()`), and a
  `Resize` event reconfigures the surface.
- **A checked CPU reference.** `check.vl` runs the same arithmetic
  star by star in f32 — *double-buffered like the GPU*: a reference
  that sweeps in place (Gauss–Seidel) reads half-updated neighbors and
  drifts from the GPU by whole partner terms, which looks like GPU
  infidelity but is the reference's bug. The GPU and the double-
  buffered CPU agree to the last bit (the comparison prints `physics
  ok` under a 4e-3 relative tolerance). The frame's light is checked
  structurally: the core sits at the center of the view, so the center
  ninth of the frame must out-shine the corners.

New to vole? `volec guide gpu` and `volec guide window` cover the APIs
this example uses.
