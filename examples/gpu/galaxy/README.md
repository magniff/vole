# galaxy

An N-body simulation of a spinning galaxy: a pinned core, a few
thousand disk stars on near-circular orbits, computed entirely on the
GPU (one `@compute` kernel over storage buffers) and rendered into a
real window (`std::window` + `std::gpu`, Metal on macOS) as
camera-facing glowing billboards — no vertex buffers, no textures.

```sh
target/volec -O2 examples/gpu/galaxy/main.vl -o galaxy
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
  infidelity but is the reference's bug. The reference keeps the exact
  `sqrt` + divide for the weight where the kernel uses the fast
  `inverseSqrt`, so the two differ by ulps per pair term — far under
  the 4e-3 relative tolerance `physics ok` checks. The frame's light is
  checked structurally: the core sits at the center of the view, so the
  center ninth of the frame must out-shine the corners.

## How fast

Everything is one O(n²) step per frame, on the GPU only — measured on
an Apple M5, one step per frame steady state:

| stars | step (ms) | what it means for the frame |
|---|---|---|
| 8 192 | 0.9 | 60 fps with a whole frame to spare |
| 16 384 | 2.4 | 60 fps comfortably |
| 32 768 | 8.7 | 60 fps within the 16.7 ms budget |
| 65 536 | 37 | ~27 fps — the direct sum's ceiling here |
| 131 072 | 161 | a few fps |

The kernel keeps the exact direct sum: one `@workgroup_size(256)`
invocation per star, star loads double-buffered through workgroup
memory (the next tile streams in while the group sums against the
current one), four partners per inner turn so the four
`inverseSqrt` chains overlap, and `g·m·inverseSqrt(r²·r²·r2)` for the
weight — those changes more than doubled the direct sum against the
naive loop (69.8 → 37 ms at 65 536 on this Mac). A direct sum cannot
reach 60 fps at 65 536 stars on this class of GPU: about 4.3 billion
pair terms per step against the instruction mix above. `--stars`
chooses your trade; `--help` lists it.

New to vole? `volec guide gpu` and `volec guide window` cover the APIs
this example uses.
