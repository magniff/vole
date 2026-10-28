# GPU: std::gpu (0.22; guide updated 0.25.2)

`std::gpu` is compute and rendering on the GPU, on wgpu's model: an
`Instance`, an `Adapter`, a `Device` and its `Queue`; `Buffer`s,
`Texture`s and their views, `Sampler`s; a `Shader`, bind groups and
compute and render pipelines; an `Encoder` whose passes are closures.
On macOS it runs on Metal. std links Metal and the Objective-C runtime
itself (its extern blocks' `#[link]`s):

```sh
volec main.vl -o prog
```

## A window: storage buffer, compute, render

The whole loop, from examples/gpu/life: a compute shader writes a
storage buffer, a render shader reads it into the window's frame. Each
WGSL module is a `Shader`; `@group(g) @binding(b)` are the bind groups'
numbers, made from `pipe.bind_layout(g)`.

```tach
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, RawSurface};
use std::window::{App, Event, WindowDesc};

const N: i64 = 256; // the field is N x N f32s

const STEP: [u8] = "struct U { time: f32, n: f32, pad0: f32, pad1: f32 }\n\
    @group(0) @binding(0) var<uniform> u: U;\n\
    @group(0) @binding(1) var<storage, read_write> field: array<f32>;\n\
    @compute @workgroup_size(8, 8) fn step(@builtin(global_invocation_id) id: vec3<u32>) {\n\
    let n = u32(u.n);\n\
    if (id.x >= n || id.y >= n) { return; }\n\
    let p = vec2<f32>(f32(id.x), f32(id.y)) / u.n;\n\
    field[id.y * n + id.x] = 0.5 + 0.5 * sin(12.0 * (p.x + p.y) + u.time);\n\
    }\n";

const DRAW: [u8] = "struct U { time: f32, n: f32, pad0: f32, pad1: f32 }\n\
    @group(0) @binding(0) var<uniform> u: U;\n\
    @group(0) @binding(1) var<storage, read> field: array<f32>;\n\
    struct V { @builtin(position) pos: vec4<f32>, @location(0) uv: vec2<f32> }\n\
    @vertex fn vs(@builtin(vertex_index) i: u32) -> V {\n\
    var p = vec2<f32>(-1.0, -1.0);\n\
    if (i == 1u) { p = vec2<f32>(3.0, -1.0); }\n\
    if (i == 2u) { p = vec2<f32>(-1.0, 3.0); }\n\
    return V(vec4<f32>(p, 0.0, 1.0), vec2<f32>(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5));\n\
    }\n\
    @fragment fn fs(v: V) -> @location(0) vec4<f32> {\n\
    let c = vec2<u32>(clamp(v.uv * u.n, vec2<f32>(0.0), vec2<f32>(u.n - 1.0)));\n\
    let h = field[c.y * u32(u.n) + c.x];\n\
    return vec4<f32>(h, 0.4 * h, 1.0 - h, 1.0);\n\
    }\n";

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    var app = match App::new_in(gpa) {
        Ok(a) => a,
        Err(_) => return Ok(()), // no display (ssh, CI)
    };
    var win = match app.window(WindowDesc::new("field", 512, 512)) {
        Ok(w) => w,
        Err(_) => return Ok(()),
    };
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    var surf = inst.surface(dev, RawSurface::MetalLayer(win.raw_surface()))?;
    let px = win.size();
    surf.configure(dev, px.w, px.h); // Format::Bgra8Unorm, vsync
    let ubuf = dev.buffer(dev.align_uniform(16), BufferUsage::UNIFORM | BufferUsage::COPY_DST);
    let field = dev.buffer(N * N * 4, BufferUsage::STORAGE);
    let step_shader = dev.shader_wgsl(STEP)?;
    let step = dev.compute_pipeline(step_shader, "step")?;
    let draw_shader = dev.shader_wgsl(DRAW)?;
    let draw = dev.render_pipeline(gpu::RenderDesc::new(draw_shader, "vs", "fs",
        Format::Bgra8Unorm))?;
    let cgroup = dev.bind_group(step.bind_layout(0),
        [gpu::bind(0, ubuf), gpu::bind(1, field)][..]);
    let rgroup = dev.bind_group(draw.bind_layout(0),
        [gpu::bind(0, ubuf), gpu::bind(1, field)][..]);
    var time: f32 = 0.0;
    win.request_frame();
    loop {
        match app.wait() {
            Ok(Event::Frame(_)) => {
                time += 1.0 / 60.0;
                let u: [f32; 4] = [time, N as f32, 0.0, 0.0];
                queue.write_buffer(ubuf, 0, gpu::bytes_of_f32(u[..]));
                match surf.frame() {
                    Ok(frame) => {
                        let target = frame.texture.view();
                        var enc = dev.encoder();
                        enc.compute_pass(|pass| {
                            pass.set_pipeline(step);
                            pass.set_bind_group(0, cgroup);
                            pass.dispatch(N / 8, N / 8); // workgroups of 8 x 8
                        });
                        enc.render_pass(PassDesc::color(target), |pass| {
                            pass.set_pipeline(draw);
                            pass.set_bind_group(0, rgroup);
                            pass.draw(0..3, 0..1); // one triangle over the frame
                        });
                        queue.submit(enc.finish());
                        frame.present(&queue);
                    }
                    Err(_) => {} // SurfaceLost: configure again on Resize
                }
                win.request_frame();
            }
            Ok(Event::Resize(_, s)) => surf.configure(dev, s.w, s.h),
            Ok(Event::Close(_)) | Ok(Event::Quit) => break,
            _ => {}
        }
    }
    Ok(())
}
```

- One shader module per pipeline kind: a compute module, and one with
  the `vs` and `fs` a `RenderDesc` names. A buffer the compute writes
  is `read_write` there and `read` in the render module.
- Per frame: `queue.write_buffer` the uniforms (`COPY_DST`), take
  `surf.frame()`, record the passes into one encoder, `submit`, then
  `frame.present(&queue)`. `win.request_frame()` asks for the next
  `Event::Frame` (`guide window`).
- Headless (tests, a server): `RawSurface::Headless` gives frames
  without a window, or render into a texture and read it back (below).

## Lifecycle

Every object is an owned value (`guide memory`): it is dropped at the
end of its scope, and dropping a resource the GPU still uses is safe
(the submitted work keeps it alive). There is no `free`.

| object | made by | used by |
|---|---|---|
| `Device`, `Queue` | `inst.adapter()?.device()?` | everything below; `queue.submit(cmds)` |
| `Buffer` | `dev.buffer(size, usage)`, `dev.buffer_init(bytes, usage)` | bind groups, copies, `map_read(dev)`, `map_write(dev)` + `unmap(dev)` |
| `Texture`, `TextureView` | `dev.texture(w, h, format, usage: ..)`, `tex.view()` | bind groups, render passes, copies |
| `Shader` | `dev.shader_wgsl(wgsl)?` (WGSL text), or `dev.shader(src)?` with `src` a `ShaderSource::msl(code, reflection)` | pipelines |
| `ComputePipeline`, `RenderPipeline` | `dev.compute_pipeline(shader, "main")?`, `dev.render_pipeline(desc)?` | passes; `pipe.bind_layout(0)` |
| `BindGroup` | `dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, buf)][..])` | `pass.set_bind_group(0, g)` |
| `Encoder`, `Commands` | `dev.encoder()`, `enc.finish()` | `enc.compute_pass(\|pass\| ..)`, `enc.render_pass(desc, \|pass\| ..)`, copies |

A mapped buffer is a view (`guide views`): `let b = buf.map_read(dev);`
waits for the GPU and views the buffer, which cannot be used while `b`
is. Shaders come from the shader compiler as a `ShaderSource`: the code
for the device's `caps().shader_kind` (MSL on Metal) and its
`Reflection` (entry points, bindings and their native slots).
`dev.shader_wgsl(text)` does it all: `std::gpu::wgsl` translates the
WGSL and its reflection feeds the pipelines (a rejected shader is a
`gpu::Error::Shader` with its `LINE:COL: error wgsl.CODE` line); a
program can also write both by hand, as below.

## Compute

```tach
use std::gpu;
use std::gpu::{BindingType, BufferUsage, Reflection, ShaderSource};

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let code = "kernel void k(device uint* xs [[buffer(0)]], uint i [[thread_position_in_grid]]) { xs[i] = xs[i] * xs[i]; }";
    var refl = Reflection::new_in(gpa);
    refl.compute("main", "k", 64);                         // entry, its MSL name, workgroup
    refl.bind(0, 0, BindingType::Storage, compute: 0);     // @group(0) @binding(0): buffer(0)
    let src = ShaderSource::msl(code, refl);
    let shader = dev.shader(src)?;
    let pipe = dev.compute_pipeline(shader, "main")?;
    var xs: Vec<u32> = Vec::new_in(gpa);
    for i in 0..64 { xs.push(i as u32); }
    var buf = dev.buffer_init(gpu::bytes_of_u32(xs.as_slice()),
        BufferUsage::STORAGE | BufferUsage::MAP_READ);
    let group = dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, buf)][..]);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(1); // one workgroup of 64
    });
    queue.submit(enc.finish());
    let squares = gpu::u32s(buf.map_read(dev));
    println(f"{squares[3]} {squares[63]}");
    Ok(())
}
```
```out
9 3969
```

The same kernel in WGSL: `@group(g) @binding(b)` are the bind groups'
numbers, and a runtime-sized array is bounds-checked against the buffer
bound there.

```tach
use std::gpu;
use std::gpu::BufferUsage;

const SQUARE: [u8] = "@group(0) @binding(0) var<storage, read_write> xs: array<u32>;\n\
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {\n\
    xs[id.x] = xs[id.x] * xs[id.x];\n\
    }";

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let shader = dev.shader_wgsl(SQUARE)?;
    let pipe = dev.compute_pipeline(shader, "main")?;
    var xs: Vec<u32> = Vec::new_in(gpa);
    for i in 0..64 { xs.push(i as u32); }
    var buf = dev.buffer_init(gpu::bytes_of_u32(xs.as_slice()),
        BufferUsage::STORAGE | BufferUsage::MAP_READ);
    let group = dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, buf)][..]);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(1);
    });
    queue.submit(enc.finish());
    let squares = gpu::u32s(buf.map_read(dev));
    println(f"{squares[3]} {squares[63]}");
    Ok(())
}
```
```out
9 3969
```

## Render to a texture

```tach
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, Reflection, ShaderSource, TextureUsage};

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let code = "#include <metal_stdlib>\nusing namespace metal;\nvertex float4 vs(uint v [[vertex_id]]) { float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) }; return float4(p[v], 0, 1); }\nfragment float4 fs() { return float4(1, 0.5, 0, 1); }\n";
    var refl = Reflection::new_in(gpa);
    refl.vertex("vs", "vs");
    refl.fragment("fs", "fs");
    let src = ShaderSource::msl(code, refl);
    let shader = dev.shader(src)?;
    let desc = gpu::RenderDesc::new(shader, "vs", "fs", Format::Rgba8Unorm);
    let pipe = dev.render_pipeline(desc)?;
    let tex = dev.texture(8, 8, Format::Rgba8Unorm, usage: TextureUsage::RENDER_ATTACHMENT | TextureUsage::COPY_SRC);
    let view = tex.view();
    var out = dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    var enc = dev.encoder();
    enc.render_pass(PassDesc::color(view), |pass| { // cleared to black, then drawn
        pass.set_pipeline(pipe);
        pass.draw(0..3, 0..1); // a triangle over the whole target
    });
    enc.copy_texture_to_buffer(tex, out, 256); // rows 256 bytes apart
    queue.submit(enc.finish());
    let px = out.map_read(dev);
    println(f"{px[0]} {px[1]} {px[2]} {px[3]}");
    Ok(())
}
```
```out
255 128 0 255
```

## Descriptors

Descriptors are structs with public fields and builder methods; the
defaults are wgpu's.

| struct | made by | fields / methods |
|---|---|---|
| `RenderDesc` | `gpu::RenderDesc::new(shader, "vs", "fs", format)` | `vertex`, `vs`, `fragment`, `fs`, `has_fs`, `state: PipelineState`; `.vertex_buffer(layout)`, `.target(format)` (another color target), `.blend(Blend::alpha(), target: 0)`, `.depth(format, compare, write)`, `.topology(Topology::LineList)`, `.cull(Cull::Back, front: FrontFace::Ccw)`, `.no_fragment()` |
| `PipelineState` | inside `RenderDesc` | `topology`, `cull`, `front_face`, `buffers`/`buffer_count`, `targets`/`target_count` (`ColorTarget { format, blend, write_mask }`), `depth: Option<DepthState { format, write, compare }>` |
| `VertexLayout` | `VertexLayout::new(stride, step: StepMode::Vertex)` | `.attribute(location, VertexFormat::Float32x2, offset)`: `@location(n)` reads it (at most 8 attributes, 8 buffers) |
| `PassDesc` | `PassDesc::color(view, clear: Color::rgba(r, g, b, a), load: Load::Clear)` | `.with_depth(view, clear: 1.0, store: false)`; `color: ColorAttachment { view, load, clear, store }` (`Load::Clear`, `Keep`, `DontCare`) |
| `TextureDesc` | `dev.texture(w, h, format, usage: .., layers: 1, mips: 1)` | `width`, `height`, `layers`, `mips`, `format`, `usage` |
| `SamplerDesc` | `SamplerDesc::nearest()`, `::linear()` | `mag`, `min`, `mip` (`Filter`), `address_u/v/w` (`AddressMode`), `lod_min`, `lod_max`, `compare: Option<Compare>`, `anisotropy` (1..16) |
| `Limits` | `dev.limits()`; `adapter.device(limits)` | wgpu's names: `max_buffer_size`, `max_bind_groups`, `max_bindings_per_group`, `min_uniform_buffer_offset_alignment`, `max_compute_workgroup_size_x`.., `max_compute_invocations_per_workgroup`, `max_compute_workgroups_per_dimension`.. |

## Usages and formats

- **Buffer usages** (`BufferUsage::`, or them together): `MAP_READ`,
  `MAP_WRITE`, `COPY_SRC`, `COPY_DST` (`queue.write_buffer`), `INDEX`,
  `VERTEX`, `UNIFORM`, `STORAGE`, `INDIRECT`. A storage buffer is
  `STORAGE` (`| MAP_READ` to read it back, `| COPY_DST` to write it from
  the CPU).
- **Texture usages** (`TextureUsage::`): `COPY_SRC`, `COPY_DST`,
  `TEXTURE_BINDING` (sampled), `STORAGE_BINDING` (a storable format),
  `RENDER_ATTACHMENT`.
- **Surface formats**: `surf.configure(dev, w, h, format, vsync: true)`
  takes `Format::Bgra8Unorm` (the default), `Bgra8UnormSrgb` or
  `Rgba16Float`; a pipeline drawing into the frame names the same one.
- **Texture formats** (`Format::`): `R8Unorm`, `R8Uint`, `Rg8Unorm`,
  `R16Float`, `R32Uint`, `R32Sint`, `R32Float`, `Rg16Float`,
  `Rgba8Unorm`, `Rgba8UnormSrgb`, `Rgba8Uint`, `Bgra8Unorm`,
  `Bgra8UnormSrgb`, `Rg32Float`, `Rgba16Float`, `Rgba32Uint`,
  `Rgba32Float`, `Depth32Float`.
- **Vertex formats** (`VertexFormat::`): `Float32`, `Float32x2`,
  `Float32x3`, `Float32x4`, `Uint32`, `Uint32x2`, `Uint32x4`, `Sint32`,
  `Unorm8x4` (four bytes read as a `vec4<f32>` in 0..1).

## Bind groups

A shader's `@group(g) @binding(b)` resources are given as a bind group
for group g: `dev.bind_group(pipe.bind_layout(g), entries)`, one entry
per binding of the layout, any order, then `pass.set_bind_group(g, group)`
before the draw or dispatch.

| WGSL | entry |
|---|---|
| `var<uniform> u: U;` | `gpu::bind(b, buf)` (`UNIFORM`), or `gpu::bind_range(b, buf, offset, size)` (offset a multiple of `dev.align_uniform(1)`, 256) |
| `var<storage, read> xs: array<T>;`, `read_write` | `gpu::bind(b, buf)` (`STORAGE`); a runtime-sized array is bounds-checked against the bound bytes |
| `var t: texture_2d<f32>;`, `texture_storage_2d<..>` | `gpu::bind_texture(b, tex.view())` |
| `var s: sampler;` | `gpu::bind_sampler(b, dev.sampler(SamplerDesc::linear()))` |

Groups are 0..3, 16 bindings a group. A layout comes from the pipeline,
so a group made for one pipeline fits another only with the same
bindings (`gpu.layout`).

## Index buffers, instancing, indirect draws

An index buffer (`INDEX`) is set with `pass.set_index_buffer(buf,
IndexFormat::Uint16 or Uint32, offset)` and drawn with
`pass.draw_indexed(indices, base_vertex, instances)`; instances are the
second range of `draw` and `draw_indexed` (`@builtin(instance_index)`,
or a vertex buffer of `StepMode::Instance`).

```tach
use std::gpu;
use std::gpu::{BufferUsage, Format, IndexFormat, PassDesc, TextureUsage, VertexFormat, VertexLayout};

const QUAD: [u8] = "@vertex fn vs(@location(0) p: vec2<f32>) -> @builtin(position) vec4<f32> {\n\
    return vec4<f32>(p, 0.0, 1.0);\n\
    }\n\
    @fragment fn fs() -> @location(0) vec4<f32> { return vec4<f32>(0.0, 1.0, 0.0, 1.0); }";

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let shader = dev.shader_wgsl(QUAD)?;
    var desc = gpu::RenderDesc::new(shader, "vs", "fs", Format::Rgba8Unorm);
    var layout = VertexLayout::new(8); // a vec2<f32> per vertex
    layout.attribute(0, VertexFormat::Float32x2, 0); // @location(0) at offset 0
    desc.vertex_buffer(layout);
    let pipe = dev.render_pipeline(desc)?;
    // four corners, two triangles: 0 1 2 and 2 1 3
    let corners: [f32; 8] = [-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0];
    let vb = dev.buffer_init(gpu::bytes_of_f32(corners[..]), BufferUsage::VERTEX);
    let idx: [u32; 6] = [0, 1, 2, 2, 1, 3];
    let ib = dev.buffer_init(gpu::bytes_of_u32(idx[..]), BufferUsage::INDEX);
    let tex = dev.texture(8, 8, Format::Rgba8Unorm,
        usage: TextureUsage::RENDER_ATTACHMENT | TextureUsage::COPY_SRC);
    let view = tex.view();
    var out = dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    var enc = dev.encoder();
    enc.render_pass(PassDesc::color(view), |pass| {
        pass.set_pipeline(pipe);
        pass.set_vertex_buffer(0, vb);
        pass.set_index_buffer(ib, IndexFormat::Uint32);
        pass.draw_indexed(0..6, 0, 0..1); // indices, base vertex, instances
    });
    enc.copy_texture_to_buffer(tex, out, 256);
    queue.submit(enc.finish());
    let px = out.map_read(dev);
    println(f"{px[0]} {px[1]} {px[2]} {px[256 * 7 + 4 * 7 + 1]}");
    Ok(())
}
```
```out
0 255 0 255
```

std::gpu has no indirect draws or dispatches yet (`draw_indirect`,
`dispatch_indirect`): `BufferUsage::INDIRECT` exists and nothing reads
it; write the counts from the CPU, or map a buffer the GPU filled.

## Uniform and storage layout

Buffers hold WGSL's layout, and the CPU writes the same bytes
(`gpu::bytes_of_f32`, `bytes_of_u32`; a `[f32; N]` array with the
padding written as zeros):

| WGSL type | align | size |
|---|---|---|
| `f32`, `i32`, `u32` | 4 | 4 |
| `vec2<T>` | 8 | 8 |
| `vec3<T>` | 16 | 12: a scalar after it fills the last 4 bytes |
| `vec4<T>` | 16 | 16 |
| `mat4x4<f32>` | 16 | 64 (columns) |
| `array<T, N>` | T's | N x the stride (T's size rounded up to its align) |
| `struct` | its largest member's | its members at their aligns, rounded up to its align |

In a `var<uniform>`, an array's stride and a nested struct's offset are
also multiples of 16 (`wgsl.layout`): use `vec4` elements, or move the
data to a storage buffer. A uniform binding's offset is a multiple of
`dev.align_uniform(1)` (256); `dev.align_uniform(n)` rounds a size up.

```tach
use std::gpu;
use std::gpu::BufferUsage;

// a: offset 0 (vec3 aligns to 16), b: 12 (in a's padding), c: 16, d: 32
const SHADER: [u8] = "struct U { a: vec3<f32>, b: f32, c: vec2<f32>, d: vec4<f32> }\n\
    @group(0) @binding(0) var<uniform> u: U;\n\
    @group(0) @binding(1) var<storage, read_write> out: array<f32>;\n\
    @compute @workgroup_size(1) fn main() {\n\
    out[0] = u.a.z; out[1] = u.b; out[2] = u.c.y; out[3] = u.d.w;\n\
    }";

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let shader = dev.shader_wgsl(SHADER)?;
    let pipe = dev.compute_pipeline(shader, "main")?;
    // the struct as WGSL lays it out: 48 bytes, 12 f32s
    let u: [f32; 12] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 0.0, 0.0, 7.0, 8.0, 9.0, 10.0];
    let ubuf = dev.buffer_init(gpu::bytes_of_f32(u[..]), BufferUsage::UNIFORM);
    var out = dev.buffer(16, BufferUsage::STORAGE | BufferUsage::MAP_READ);
    let group = dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, ubuf), gpu::bind(1, out)][..]);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(1);
    });
    queue.submit(enc.finish());
    let r = gpu::f32s(out.map_read(dev));
    println(f"{r[0]} {r[1]} {r[2]} {r[3]}");
    Ok(())
}
```
```out
3 4 6 10
```

## Workgroups

`@compute @workgroup_size(x, y, z)` is one workgroup's invocations (1 to
1024 in all); `pass.dispatch(gx, gy, gz)` runs gx x gy x gz workgroups,
so cover n items with `(n + x - 1) / x` and return early in the shader
past n (`@builtin(global_invocation_id)`). `var<workgroup>` memory is
shared within a workgroup; `workgroupBarrier()` orders it. A size above
`dev.limits()` is an `Error::Pipeline` from `compute_pipeline`.

## What the translation rejects

`dev.shader_wgsl` runs std::gpu::wgsl's front end, then Metal's compiler
on the MSL it writes. Everything is an `Err(gpu::Error::Shader(m))` with
the position in the WGSL, never a panic (`wgslc explain CODE`):

- The front end takes the subset of docs/design/gpu.md (section 2.10) and
  rejects the rest at its line: `wgsl.unsupported` (f16, `override`,
  `const_assert`, extensions, cube, 3D and multisampled textures,
  pointer parameters beyond function and private ones),
  `wgsl.recursion`, `wgsl.layout` (the uniform rules above),
  `wgsl.attr` (a workgroup size outside 1..1024), `wgsl.binding`, and
  the type and name errors of WGSL.
- Names are never a problem: an identifier Metal keeps for itself
  (`quad`, `float4`, `half`, `kernel`, `INFINITY`, `M_PI_F`, `assert`,
  any C++ keyword) is renamed in the MSL; entry points keep their WGSL
  names for `compute_pipeline` and `RenderDesc`.
- What Metal still rejects is a translator bug: `LINE:COL: error
  wgsl.target: Metal rejected the translation of fn NAME: ...` at that
  WGSL function, then Metal's log. Report it; rename or rewrite the
  function meanwhile.
- More than 16 runtime-sized storage bindings in a module (the sizes
  buffer that bounds their indices) is an `Error::Shader` too.

## Capabilities

`dev.caps()` says what the device can do: `compute`, `render`,
`surfaces`, `textures`, `unified_memory` (information only: mapping
behaves the same either way) and `shader_kind` (`ShaderKind::Msl`,
`Spirv`, `Ptx`). A compute-only backend reports `render: false`, and
every render, texture and surface call `requires` its flag
(`gpu.unsupported`). Backends implement `std::gpu::hal::Api` (and
`hal::Render` when they draw); the API never depends on one's memory
model.

## Contracts

Misuse stops the program at the call, `FILE:LINE:COL: gpu.CODE: ...`,
exit 101 (`guide contracts`); what can fail however correct the program
is (no adapter, a shader the driver rejects) is a `gpu::Error`.

| code | the rule | the fix |
|---|---|---|
| `gpu.usage` | a buffer or texture used without the usage flag that allows it | add it at creation: `BufferUsage::STORAGE \| BufferUsage::COPY_SRC` |
| `gpu.align` | offsets: 256 for uniform and storage bindings, 4 for copies; rows 256 | `dev.align_uniform(n)` |
| `gpu.range` | an offset, size or draw range past its buffer or texture | the sizes |
| `gpu.layout` | a bind group that does not match the pipeline's layout | make it from `pipe.bind_layout(i)` |
| `gpu.pipeline` | a draw or dispatch without a pipeline or a bind group it uses | `pass.set_pipeline`, `pass.set_bind_group` |
| `gpu.format` | a format that does not fit: target, view, storage, shader kind | the pipeline's target format |
| `gpu.limits` | a size or count above `dev.limits()` (what a shader asks, its workgroup size or bindings, is an `Err` instead) | smaller |
| `gpu.state` | a buffer used while mapped for writing | `buf.unmap(dev)` first |
| `gpu.unsupported` | a capability the device lacks | check `dev.caps()` |

Surfaces (`inst.surface(dev, RawSurface::MetalLayer(layer))`,
`surf.configure(..)`, `surf.frame()?`, `frame.present(&queue)`) are
what std::window draws into; `RawSurface::Headless` gives frames without
a window.
