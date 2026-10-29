# GPU: std::gpu (0.22; guide updated 0.25.3)

`std::gpu` is compute and rendering on the GPU, on wgpu's model: an
`Instance`, an `Adapter`, a `Device` and its `Queue`; `Buffer`s,
`Texture`s and their views, `Sampler`s; a `Shader`, bind groups and
compute and render pipelines; an `Encoder` whose passes are closures.
On macOS it runs on Metal. std links Metal and the Objective-C runtime
itself (its extern blocks' `#[link]`s):

```sh
volec main.vl -o prog
```

## Skeleton

A window program whole: a compute pass writes a storage buffer, a
render pass draws from it into the window's frame, and at the end a
readback copies the buffer into a `MAP_READ | COPY_DST` one and maps
that. The other sections grow parts of it.

```vole
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, RawSurface, RenderDesc};
use std::window::{App, Event, WindowDesc};

const STEP: [u8] = """
    @group(0) @binding(0) var<storage, read_write> v: array<f32>;
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        v[id.x] += 0.01;
    }
    """;
const DRAW: [u8] = """
    @group(0) @binding(0) var<storage, read> v: array<f32>;
    @vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
        return vec4<f32>(select(-1.0, 3.0, i == 1u), select(-1.0, 3.0, i == 2u), 0.0, 1.0);
    }
    @fragment fn fs() -> @location(0) vec4<f32> { return vec4<f32>(fract(v[0]), 0.3, 0.5, 1.0); }
    """;

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    var app = match App::new_in(gpa) {
        Ok(a) => a,
        Err(_) => return Ok(()), // no display (ssh, CI)
    };
    var win = match app.window(WindowDesc::new("skeleton", 640, 480)) {
        Ok(w) => w,
        Err(_) => return Ok(()),
    };
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    var surf = inst.surface(dev, RawSurface::MetalLayer(win.raw_surface()))?;
    let px = win.size();
    surf.configure(dev, px.w, px.h); // Format::Bgra8Unorm, vsync
    let cells = dev.buffer(64 * 4, BufferUsage::STORAGE | BufferUsage::COPY_SRC);
    let step = dev.compute_pipeline(dev.shader_wgsl(STEP)?, "main")?;
    let draw_shader = dev.shader_wgsl(DRAW)?;
    let draw = dev.render_pipeline(RenderDesc::new(draw_shader, "vs", "fs", Format::Bgra8Unorm))?;
    let sgroup = dev.bind_group(step.bind_layout(0), [gpu::bind(0, cells)][..]);
    let dgroup = dev.bind_group(draw.bind_layout(0), [gpu::bind(0, cells)][..]);
    var frames = 0;
    win.request_frame();
    while frames < 120 {
        match app.wait() {
            Ok(Event::Frame(_)) => {
                if let Ok(frame) = surf.frame() {
                    let target = frame.texture.view();
                    var enc = dev.encoder();
                    enc.compute_pass(|pass| {
                        pass.set_pipeline(step);
                        pass.set_bind_group(0, sgroup);
                        pass.dispatch(1); // one workgroup of 64
                    });
                    enc.render_pass(PassDesc::color(target), |pass| {
                        pass.set_pipeline(draw);
                        pass.set_bind_group(0, dgroup);
                        pass.draw(0..3, 0..1); // one triangle over the frame
                    });
                    queue.submit(enc.finish());
                    frame.present(&queue);
                }
                frames += 1;
                win.request_frame();
            }
            Ok(Event::Resize(_, s)) => surf.configure(dev, s.w, s.h),
            Ok(Event::Close(_)) | Ok(Event::Quit) => break,
            _ => {}
        }
    }
    // the readback: a copy into a MAP_READ | COPY_DST buffer, mapped
    var rb = dev.buffer(64 * 4, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    var enc = dev.encoder();
    enc.copy_buffer(cells, 0, rb, 0, 64 * 4);
    queue.submit(enc.finish());
    let v = gpu::f32s(rb.map_read(dev));
    println(f"{frames} frames, v[0] = {v[0]}");
    Ok(())
}
```

- Each WGSL module is a `Shader`; `@group(g) @binding(b)` are the bind
  groups' numbers, a group made from `pipe.bind_layout(g)`
  (`gpu#bind-groups`). A buffer the compute writes is `read_write`
  there and `read` in the render module.
- Per frame: `queue.write_buffer` the uniforms (`COPY_DST`), take
  `surf.frame()`, record the passes into one encoder, `submit`, then
  `frame.present(&queue)`; `win.request_frame()` asks for the next
  `Event::Frame`, and `Event::Resize` configures the surface again
  (`guide window`).
- The handles (`dev`, `cells`, `step`, ...) move: keep them in one
  owner, `gpu#handles`. Headless (tests, a server):
  `RawSurface::Headless` gives frames without a window; reading them
  back to check a windowed program's pixels: `window#checking-the-pixels-headless`.

@PAGE-END@ More, a section at a time (`volec guide gpu#NAME`; `volec guide gpu#` lists them): `handles` (which objects move; keeping them in a struct, a Vec, a closure), `lifecycle` (the objects; mapping and readback), `compute`, `ordering` (dispatches in a pass), `bind-groups`, `one-module-per-kernel`, `uniform-and-storage-layout`, `workgroups`, `buffer-sizes`, `atomics`, `ping-pong`, `per-step-parameters`, `timing-gpu-work`, `what-the-translation-rejects`, `contracts` (the gpu.* stops). Rendering: `volec guide gpu-render`; the window and the mouse: `volec guide window`. All of it: `volec guide gpu --whole`.

## Handles

std::gpu's objects are owned values (`guide memory`): each has one
owner, and `let w = v;`, a struct literal, a tuple, `Vec::push` or a
`sink` parameter moves it; none has `.clone()`. Which move and which
copy (`volec query own FILE:LINE:COL` says it of each local):

| kind | types |
|---|---|
| owned: moves | `Adapter`, `Device`, `Queue`, `Buffer`, `Texture`, `TextureView`, `Sampler`, `Shader`, `ComputePipeline`, `RenderPipeline`, `BindGroup`, `Encoder`, `Commands`, `Surface`, `Frame` |
| plain: copies | `Instance`, `BindLayout` (`pipe.bind_layout(g)`), `Limits`, `Caps`, `Format`, `Color`, `SamplerDesc`, `VertexLayout`, the usage flags (`u32`) |
| view | `RenderDesc` (of its shader), `PassDesc` (of its texture views): made where they are used |

- Lending a handle moves nothing. A function that reads one takes it
  let, `fn draw(dev: gpu::Device, pipe: gpu::RenderPipeline)`, called
  `draw(dev, pipe)`; `inout` where it changes (`queue: inout
  gpu::Queue` to `submit`, `buf: inout gpu::Buffer` to `map_read`);
  `sink` only to keep it.
- Keep them in a struct, made by a constructor that takes them `sink`
  (`Gpu::new(dev, queue, gpa)` below); from then on they are `g.dev`,
  `self.queue`. Many of a kind: a `Vec` (`bufs.push(b)` moves `b`;
  `bufs[i]` and `bufs.get(i)` read it in place) or an array,
  `[gpu::BindGroup; 2]`.
- In a closure (`enc.compute_pass(|pass| ..)`) name the field itself,
  `self.pipe`, or a let local of it, `let pipe = self.pipe;`: a let of
  a field or an element views it (`guide memory#moves-and-drops`) and
  moves nothing. A tuple moves: `let (a, b) = (self.a, self.b);` is
  `own.move_out`.
- One of two by a flag: `let g = if odd { self.g1 } else { self.g0 };`
  moves too (`own.move_out`). Call in each branch, `if odd {
  pass.set_bind_group(0, self.g1); } else { pass.set_bind_group(0,
  self.g0); }`, or keep the two in an array and index it,
  `self.groups[k]`:

```vole
use std::gpu;
use std::gpu::BufferUsage;

const ADD: [u8] = """
    @group(0) @binding(0) var<storage, read_write> xs: array<u32>;
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        xs[id.x] += 1u;
    }
    """;

// The program's handles, with one owner.
struct Gpu {
    dev: gpu::Device,
    queue: gpu::Queue,
    pipe: gpu::ComputePipeline,
    bufs: Vec<gpu::Buffer>,
    groups: [gpu::BindGroup; 2],
}

impl Gpu {
    fn new(dev: sink gpu::Device, queue: sink gpu::Queue, gpa: Gpa) -> Result<Gpu, gpu::Error> {
        let pipe = dev.compute_pipeline(dev.shader_wgsl(ADD)?, "main")?;
        var bufs: Vec<gpu::Buffer> = Vec::new_in(gpa);
        for _ in 0..2 {
            bufs.push(dev.buffer(64 * 4, BufferUsage::STORAGE | BufferUsage::COPY_SRC));
        }
        let layout = pipe.bind_layout(0); // plain: a copy
        let groups = [
            dev.bind_group(layout, [gpu::bind(0, bufs[0])][..]),
            dev.bind_group(layout, [gpu::bind(0, bufs[1])][..]),
        ];
        Ok(Gpu { dev: dev, queue: queue, pipe: pipe, bufs: bufs, groups: groups })
    }

    // Adds 1 to buffer k's elements, n times.
    fn add(inout self, k: i64, n: i64) {
        let pipe = self.pipe; // views the field: nothing moves
        var enc = self.dev.encoder();
        enc.compute_pass(|pass| {
            pass.set_pipeline(pipe);
            for _ in 0..n {
                pass.set_bind_group(0, self.groups[k]); // the field itself
                pass.dispatch(1);
            }
        });
        self.queue.submit(enc.finish());
    }

    fn first(inout self, k: i64) -> u32 {
        var rb = self.dev.buffer(4, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
        var enc = self.dev.encoder();
        enc.copy_buffer(self.bufs[k], 0, rb, 0, 4);
        self.queue.submit(enc.finish());
        gpu::u32s(rb.map_read(self.dev))[0]
    }
}

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa); // plain
    let (dev, queue) = inst.adapter()?.device()?;
    var g = Gpu::new(dev, queue, gpa)?; // dev and queue moved: g.dev from here
    g.add(0, 3);
    g.add(1, 5);
    println(f"{g.first(0)} {g.first(1)}");
    Ok(())
}
```
```out
3 5
```

## Lifecycle

Every object is an owned value (`guide memory`; which move and how to
keep them: `gpu#handles`): it is dropped at the end of its scope, and
dropping a resource the GPU still uses is safe (the submitted work
keeps it alive). There is no `free`.

| object | made by | used by |
|---|---|---|
| `Device`, `Queue` | `inst.adapter()?.device()?` | everything below; `queue.submit(cmds)` |
| `Buffer` | `dev.buffer(size, usage)`, `dev.buffer_init(bytes, usage)` | bind groups, copies, `map_read(dev)`, `map_write(dev)` + `unmap(dev)` |
| `Texture`, `TextureView` | `dev.texture(w, h, format, usage: ..)`, `tex.view()` | bind groups, render passes, copies |
| `Shader` | `dev.shader_wgsl(wgsl)?` (WGSL text), or `dev.shader(src)?` with `src` a `ShaderSource::msl(code, reflection)` | pipelines |
| `ComputePipeline`, `RenderPipeline` | `dev.compute_pipeline(shader, "main")?`, `dev.render_pipeline(desc)?` | passes; `pipe.bind_layout(0)` |
| `BindGroup` | `dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, buf)][..])` | `pass.set_bind_group(0, g)` |
| `Encoder`, `Commands` | `dev.encoder()`, `enc.finish()` | `enc.compute_pass(\|pass\| ..)`, `enc.render_pass(desc, \|pass\| ..)`, copies |

A mappable buffer is reached by copies only (WebGPU's rule, `gpu.usage`
at `dev.buffer`, 0.25.3): `MAP_READ` goes with `COPY_DST` alone,
`MAP_WRITE` with `COPY_SRC` alone. A kernel's output is a `STORAGE |
COPY_SRC` buffer, copied (`enc.copy_buffer`) into a `MAP_READ |
COPY_DST` one that is mapped (the compute examples below).

A mapped buffer is a view (`guide views`): `let b = buf.map_read(dev);`
waits for the GPU and views the buffer's bytes (`gpu::f32s(b)`,
`u32s`, `i32s`: the same bytes as numbers, still a view of `buf`). The
buffer stays **mapped until `buf.unmap(dev)`**, and nothing writes a
mapped buffer, so a view never changes under the program: a copy into
it (or `queue.write_buffer`) stops with `gpu.state`, when it is
recorded, or at `queue.submit` when it was recorded before the
`map_read`. `unmap` takes the buffer `inout`, so it is refused
(`own.conflict`) while a view of it is still used: read what you need,
`unmap`, then copy into it again (the atomics example below). Mapping
again while mapped is fine. `buf.map_read_copy_in(dev, gpa)` maps,
copies the bytes into a `Vec<u8>` (`gpu::f32s(v.as_slice())`) and
unmaps: the buffer can be written again at once, and the copy outlives
it. A view lives no longer than the buffer: a function may return
`buf.map_read(dev)` when `buf` is its caller's (an `inout` parameter),
not when the buffer is a local of its own (`own.escape`); then return
`map_read_copy_in`'s copy. A function of your own that returns
`gpu::f32s(buf.map_read(dev))` of an `inout` parameter views `buf`
too (inferred, `volec query views NAME`).

Shaders come from the shader compiler as a `ShaderSource`: the code
for the device's `caps().shader_kind` (MSL on Metal) and its
`Reflection` (entry points, bindings and their native slots).
`dev.shader_wgsl(text)` does it all: `std::gpu::wgsl` translates the
WGSL and its reflection feeds the pipelines (a rejected shader is a
`gpu::Error::Shader` with its `LINE:COL: error wgsl.CODE` line); a
program can also write both by hand, as below.

## Compute

```vole
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
    let buf = dev.buffer_init(gpu::bytes_of_u32(xs.as_slice()),
        BufferUsage::STORAGE | BufferUsage::COPY_SRC);
    var out = dev.buffer(64 * 4, BufferUsage::MAP_READ | BufferUsage::COPY_DST); // the readback
    let group = dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, buf)][..]);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(1); // one workgroup of 64
    });
    enc.copy_buffer(buf, 0, out, 0, 64 * 4);
    queue.submit(enc.finish());
    let squares = gpu::u32s(out.map_read(dev));
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

```vole
use std::gpu;
use std::gpu::BufferUsage;

const SQUARE: [u8] = r"""
    @group(0) @binding(0) var<storage, read_write> xs: array<u32>;
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        xs[id.x] = xs[id.x] * xs[id.x];
    }
    """;

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let shader = dev.shader_wgsl(SQUARE)?;
    let pipe = dev.compute_pipeline(shader, "main")?;
    var xs: Vec<u32> = Vec::new_in(gpa);
    for i in 0..64 { xs.push(i as u32); }
    let buf = dev.buffer_init(gpu::bytes_of_u32(xs.as_slice()),
        BufferUsage::STORAGE | BufferUsage::COPY_SRC);
    var out = dev.buffer(64 * 4, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    let group = dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, buf)][..]);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(1);
    });
    enc.copy_buffer(buf, 0, out, 0, 64 * 4);
    queue.submit(enc.finish());
    let squares = gpu::u32s(out.map_read(dev));
    println(f"{squares[3]} {squares[63]}");
    Ok(())
}
```
```out
9 3969
```

## Ordering

What runs after what, as std's Metal backend runs it:

- **Dispatches in one compute pass** run in order, each seeing every
  write of the ones before, from any workgroup: the backend's compute
  encoder is Metal's serial kind, which starts a dispatch when the one
  before has finished, and std's buffers are tracked by Metal, so no
  barrier is written. Many dispatches in one `compute_pass` (and one
  submit) is the normal shape for a sequence of kernels, a model's
  layers or a simulation's steps (`gpu#ping-pong`): `set_pipeline` and
  `set_bind_group` between them are cheap, while a pass or a submit
  each costs more (an LLM's decoding gained about 10% from one pass a
  token instead of one a kernel).
- **The passes and copies of one encoder** run in the order recorded,
  and **submits** in the order made (each after everything submitted
  before).
- **`queue.write_buffer`** lands before the commands of the next submit:
  the steps recorded in one encoder all see the last value written
  (`gpu#per-step-parameters`).
- **Within one dispatch** the invocations run in no order: one sees
  another's write only through atomics (`gpu#atomics`), or in one
  workgroup through `var<workgroup>` memory and `workgroupBarrier()`.

```vole
use std::gpu;
use std::gpu::BufferUsage;

const FILL: [u8] = """
    @group(0) @binding(0) var<storage, read_write> xs: array<u32>;
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        xs[id.x] = id.x * id.x;
    }
    """;

// reads what other workgroups of FILL wrote
const REVERSE: [u8] = """
    @group(0) @binding(0) var<storage, read> xs: array<u32>;
    @group(0) @binding(1) var<storage, read_write> ys: array<u32>;
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        ys[id.x] = xs[255u - id.x];
    }
    """;

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let fill = dev.compute_pipeline(dev.shader_wgsl(FILL)?, "main")?;
    let reverse = dev.compute_pipeline(dev.shader_wgsl(REVERSE)?, "main")?;
    let xs = dev.buffer(256 * 4, BufferUsage::STORAGE);
    let ys = dev.buffer(256 * 4, BufferUsage::STORAGE | BufferUsage::COPY_SRC);
    let fgroup = dev.bind_group(fill.bind_layout(0), [gpu::bind(0, xs)][..]);
    let rgroup = dev.bind_group(reverse.bind_layout(0), [gpu::bind(0, xs), gpu::bind(1, ys)][..]);
    var rb = dev.buffer(256 * 4, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(fill);
        pass.set_bind_group(0, fgroup);
        pass.dispatch(4);
        pass.set_pipeline(reverse); // runs after the fill, seeing all it wrote
        pass.set_bind_group(0, rgroup);
        pass.dispatch(4);
    });
    enc.copy_buffer(ys, 0, rb, 0, 256 * 4); // after the pass
    queue.submit(enc.finish());
    let got = gpu::u32s(rb.map_read(dev));
    var wrong = 0;
    for i in 0..256 {
        if got[i] != ((255 - i) * (255 - i)) as u32 { wrong += 1; }
    }
    println(f"{got[0]} {got[255]}, {wrong} wrong");
    Ok(())
}
```
```out
65025 0, 0 wrong
```

## Rendering

Render passes into textures, a textured quad (a vertex layout of several
attributes, `write_texture`, a sampler), several color targets, and
depth-only passes: `volec guide gpu-render`. A window's frame is drawn
the same way (the first example, and `guide window`).

## Descriptors

Descriptors are structs with public fields and builder methods; the
defaults are wgpu's.

| struct | made by | fields / methods |
|---|---|---|
| `RenderDesc` | `gpu::RenderDesc::new(shader, "vs", "fs", format)`; `RenderDesc::depth_only(shader, "vs", format: Format::Depth32Float, compare: Compare::Less)` | `vertex`, `vs`, `fragment`, `fs`, `has_fs`, `state: PipelineState`; `.vertex_buffer(layout)`, `.target(format)` (another color target), `.blend(Blend::alpha(), target: 0)`, `.depth(format, compare, write)`, `.topology(Topology::LineList)`, `.cull(Cull::Back, front: FrontFace::Ccw)`, `.no_fragment()` (no fragment stage, no color target) |
| `PipelineState` | inside `RenderDesc` | `topology`, `cull`, `front_face`, `buffers`/`buffer_count`, `targets`/`target_count` (`ColorTarget { format, blend, write_mask }`), `depth: Option<DepthState { format, write, compare }>` |
| `VertexLayout` | `VertexLayout::new(stride, step: StepMode::Vertex)` | `.attribute(location, VertexFormat::Float32x2, offset)`: `@location(n)` reads it (at most 8 attributes, 8 buffers) |
| `PassDesc` | `PassDesc::color(view, clear: Color::rgba(r, g, b, a), load: Load::Clear)`; `PassDesc::depth_only(view, clear: 1.0, store: true)` | `.with_color(view, clear, load)` (the next color attachment, up to 8), `.with_depth(view, clear: 1.0, store: false)`; `colors: [Option<ColorAttachment>; 8]` and `color_count` (`ColorAttachment { view, load, clear, store }`; `Load::Clear`, `Keep`, `DontCare`), `depth: Option<DepthAttachment>` |
| `TextureDesc` | `dev.texture(w, h, format, usage: .., layers: 1, mips: 1)` | `width`, `height`, `layers`, `mips`, `format`, `usage` |
| `SamplerDesc` | `SamplerDesc::nearest()`, `::linear()` | `mag`, `min`, `mip` (`Filter`), `address_u/v/w` (`AddressMode`), `lod_min`, `lod_max`, `compare: Option<Compare>`, `anisotropy` (1..16) |
| `Limits` | `Limits::default()`, `adapter.limits()` (the most it takes), `dev.limits()`; `adapter.device(limits)` | wgpu's names: `max_buffer_size`, `max_bind_groups`, `max_bindings_per_group`, `min_uniform_buffer_offset_alignment`, `max_compute_workgroup_size_x`.., `max_compute_invocations_per_workgroup`, `max_compute_workgroups_per_dimension`.. (Buffer sizes, below) |

## Usages and formats

- **Buffer usages** (`BufferUsage::`, or them together): `MAP_READ`,
  `MAP_WRITE`, `COPY_SRC`, `COPY_DST` (`queue.write_buffer`), `INDEX`,
  `VERTEX`, `UNIFORM`, `STORAGE`, `INDIRECT`. A storage buffer is
  `STORAGE` (`| COPY_SRC` to copy it into a `MAP_READ | COPY_DST`
  buffer and read it back, `| COPY_DST` to write it from the CPU).
  `MAP_READ` takes `COPY_DST` alone and `MAP_WRITE` `COPY_SRC` alone
  (`gpu.usage`). They are `u32` bit flags (`const`s of `BufferUsage`, not an
  enum): a usage is a `u32`, `let u: u32 = BufferUsage::UNIFORM |
  BufferUsage::COPY_DST;`, and `buf.usage & BufferUsage::STORAGE != 0`
  tests one. `TextureUsage::` is the same.
- **Texture usages** (`TextureUsage::`): `COPY_SRC`, `COPY_DST`,
  `TEXTURE_BINDING` (sampled), `STORAGE_BINDING` (a storable format),
  `RENDER_ATTACHMENT`.
- **Storable formats** (`STORAGE_BINDING`, `texture_storage_2d<F,
  write>`; `Format::is_storable` says the same): `R32Uint`, `R32Sint`,
  `R32Float`, `Rgba8Unorm`, `Rgba8Uint`, `Rg32Float`, `Rgba16Float`,
  `Rgba32Uint`, `Rgba32Float` (WGSL `r32uint` .. `rgba32float`).
  Storage textures are written only (`write`), never read: a kernel that
  reads its last frame reads it as a `texture_2d` (bound beside, from
  another texture).
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

A layout holds the bindings the pipeline's **own entry points use**
(its kernel; its vertex and fragment entry points), through the
functions they call: WebGPU's `layout: "auto"`. A binding declared and
used by none of them is not in it, nor one only another entry point of
the module uses (0.25.2.2; before, every entry point of the module in
the pipeline's stages added its bindings). So a bind group with an
entry for every declared binding fails, and `gpu.layout` names the
layout's bindings:

```text
main.vl:135:17: gpu.layout: the layout has 2 bindings, 0 and 3, and binding 1 of the bind group does not fit them: a layout is the bindings the pipeline's own entry points use, ...
```

`pipe.bind_layout(g).entries[i].binding` (i below `.count`) lists them.

## One module per kernel

Give each compute kernel its own shader module: one `dev.shader_wgsl`
each, its text a shared prefix (structs, the uniform, helper functions)
and the kernel. The reasons:

- Two variables of one module never share a `@group @binding`, even when
  different entry points use them (`wgsl.binding: @group(0) @binding(0)
  is also 'a'`), so one module of many kernels needs a distinct binding
  for every buffer of every kernel.
- A kernel's own bind group then needs exactly what it uses, in either
  shape (a pipeline's layout is its entry point's bindings): one module
  of several kernels works too, each kernel with a group of its own
  bindings (the next example's clear binds one buffer, the deposit
  two).

The helper the examples use: a compute pipeline from the module made of
`parts` (a shared prefix and one kernel), its entry point `main`.

```vole
use std::gpu;

fn kernel(dev: gpu::Device, parts: [[u8]], gpa: Gpa) -> Result<gpu::ComputePipeline, gpu::Error> {
    var src = Buf::new_in(gpa);
    for p in parts {
        src.push_str(p);
    }
    let shader = dev.shader_wgsl(src.as_slice())?;
    dev.compute_pipeline(shader, "main")
}
```

## Index buffers, instancing, indirect draws

An index buffer (`INDEX`) is set with `pass.set_index_buffer(buf,
IndexFormat::Uint16 or Uint32, offset)` and drawn with
`pass.draw_indexed(indices, base_vertex, instances)`; instances are the
second range of `draw` and `draw_indexed` (`@builtin(instance_index)`,
or a vertex buffer of `StepMode::Instance`).

```vole
use std::gpu;
use std::gpu::{BufferUsage, Format, IndexFormat, PassDesc, TextureUsage, VertexFormat, VertexLayout};

const QUAD: [u8] = r"""
    @vertex fn vs(@location(0) p: vec2<f32>) -> @builtin(position) vec4<f32> {
        return vec4<f32>(p, 0.0, 1.0);
    }
    @fragment fn fs() -> @location(0) vec4<f32> { return vec4<f32>(0.0, 1.0, 0.0, 1.0); }
    """;

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

A uniform buffer is read only after something wrote it: `queue.write_buffer`
(before the submit that reads it; its zeros from `dev.buffer` are no
value), `dev.buffer_init(bytes, ..)`, a copy into it, or a kernel
writing it as storage. A submit whose dispatch or draw reads one that
nothing wrote stops at the `queue.submit` line (0.25.2.2; before, the
kernel read zeros: a guard on `u.n` wrote nothing, silently):

```text
main.vl:52:5: gpu.unwritten: binding 0 of group 0 (a uniform buffer of 256 bytes) was never written: write it (queue.write_buffer) before submitting the first dispatch or draw that reads it ...
```

For the other bindings, a readback after the first step shows what a
kernel saw (a storage buffer written from the uniform's fields, copied
into a `MAP_READ` one), and `dev.buffer_init` gives a buffer its bytes
when it is made.

In a `var<uniform>`, an array's stride and a nested struct's offset are
also multiples of 16 (`wgsl.layout`): use `vec4` elements, or move the
data to a storage buffer. A uniform binding's offset is a multiple of
`dev.align_uniform(1)` (256); `dev.align_uniform(n)` rounds a size up.

```vole
use std::gpu;
use std::gpu::BufferUsage;

// a: offset 0 (vec3 aligns to 16), b: 12 (in a's padding), c: 16, d: 32
const SHADER: [u8] = r"""
    struct U { a: vec3<f32>, b: f32, c: vec2<f32>, d: vec4<f32> }
    @group(0) @binding(0) var<uniform> u: U;
    @group(0) @binding(1) var<storage, read_write> out: array<f32>;
    @compute @workgroup_size(1) fn main() {
        out[0] = u.a.z; out[1] = u.b; out[2] = u.c.y; out[3] = u.d.w;
    }
    """;

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let shader = dev.shader_wgsl(SHADER)?;
    let pipe = dev.compute_pipeline(shader, "main")?;
    // the struct as WGSL lays it out: 48 bytes, 12 f32s
    let u: [f32; 12] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 0.0, 0.0, 7.0, 8.0, 9.0, 10.0];
    let ubuf = dev.buffer_init(gpu::bytes_of_f32(u[..]), BufferUsage::UNIFORM);
    let out = dev.buffer(16, BufferUsage::STORAGE | BufferUsage::COPY_SRC);
    var rb = dev.buffer(16, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    let group = dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, ubuf), gpu::bind(1, out)][..]);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(1);
    });
    enc.copy_buffer(out, 0, rb, 0, 16);
    queue.submit(enc.finish());
    let r = gpu::f32s(rb.map_read(dev));
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
`dev.limits()` is an `Error::Pipeline` from `compute_pipeline`. A
dimension of `dispatch` is at most
`dev.limits().max_compute_workgroups_per_dimension` (65535): a large 1-D
job is `dispatch(gx, gy)` with the index `id.y * gx * x + id.x`.

## Buffer sizes

A buffer is at most `dev.limits().max_buffer_size` bytes:
`Limits::default()`'s 1 GiB, wgpu's model (its default is a size every
adapter takes, 256 MiB there; more is asked for). Model weights of
several GB ask for more when opening the device, up to the adapter's
largest, `adapter.limits().max_buffer_size` (Metal's maxBufferLength,
several GiB on Apple silicon); beyond it `device(lim)` stops with
`gpu.limits` and both numbers. A buffer over the device's limit is
`gpu.limits` at its `dev.buffer` line, with the size to ask for.

```vole
use std::gpu;
use std::gpu::{BufferUsage, Limits};

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let adapter = inst.adapter()?;
    var lim = Limits::default();
    lim.max_buffer_size = 2 << 30; // 2 GiB
    let (dev, var _queue) = adapter.device(lim)?;
    println(f"{dev.limits().max_buffer_size >> 30} GiB, the adapter's {adapter.limits().max_buffer_size >= 2 << 30}");
    let _small = dev.buffer(1 << 20, BufferUsage::STORAGE); // 1 MiB
    Ok(())
}
```
```out
2 GiB, the adapter's true
```

`adapter.device(adapter.limits())` asks for all of it.

## Atomics

Many invocations adding into one place (a histogram, particles
depositing into a grid) need atomics: an `array<atomic<u32>>` (or
`atomic<i32>`) in a `var<storage, read_write>` (always `read_write`, even
for a kernel that only `atomicLoad`s: WGSL allows atomics in no other
storage access, since another invocation may write them meanwhile;
`var<storage, read>` is `wgsl.type: atomics need 'var<storage,
read_write>'`), changed with
`atomicAdd(&a[i], v)`, `atomicSub`, `atomicMax`, `atomicMin`,
`atomicExchange`, read with `atomicLoad` and set with `atomicStore`;
`var<workgroup>` atomics too. A plain `a[i] = a[i] + 1u` from several
invocations loses updates. Clearing is a kernel of its own (or
`queue.write_buffer` of zeros, or a `copy_buffer` from a zero buffer)
before the next deposit; the CPU reads the buffer as plain `u32`s.

```vole
use std::gpu;
use std::gpu::BufferUsage;

const BINS: [u8] = "@group(0) @binding(0) var<storage, read_write> bins: array<atomic<u32>>;\n";

const DEPOSIT: [u8] = r"""
    @group(0) @binding(1) var<storage, read> xs: array<u32>;
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        if (id.x >= 256u) { return; }
        atomicAdd(&bins[xs[id.x] % 4u], 1u);
    }
    """;

const CLEAR: [u8] = r"""
    @compute @workgroup_size(4) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        atomicStore(&bins[id.x], 0u);
    }
    """;

fn kernel(dev: gpu::Device, parts: [[u8]], gpa: Gpa) -> Result<gpu::ComputePipeline, gpu::Error> {
    var src = Buf::new_in(gpa);
    for p in parts {
        src.push_str(p);
    }
    let shader = dev.shader_wgsl(src.as_slice())?;
    dev.compute_pipeline(shader, "main")
}

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let deposit = kernel(dev, [BINS, DEPOSIT][..], gpa)?;
    let clear = kernel(dev, [BINS, CLEAR][..], gpa)?;
    var xs: Vec<u32> = Vec::new_in(gpa);
    for i in 0..256 { xs.push(i as u32); }
    let xb = dev.buffer_init(gpu::bytes_of_u32(xs.as_slice()), BufferUsage::STORAGE);
    let bins = dev.buffer(16, BufferUsage::STORAGE | BufferUsage::COPY_SRC);
    var rb = dev.buffer(16, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    // each module's layout has the bindings it uses: two, and one
    let dgroup = dev.bind_group(deposit.bind_layout(0), [gpu::bind(0, bins), gpu::bind(1, xb)][..]);
    let cgroup = dev.bind_group(clear.bind_layout(0), [gpu::bind(0, bins)][..]);
    println(f"layouts: {deposit.bind_layout(0).count} and {clear.bind_layout(0).count}");
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(deposit);
        pass.set_bind_group(0, dgroup);
        pass.dispatch(4); // 256 items deposit
        pass.dispatch(4); // and again: 128 a bin
    });
    enc.copy_buffer(bins, 0, rb, 0, 16);
    queue.submit(enc.finish());
    let twice = gpu::u32s(rb.map_read(dev));
    println(f"{twice[0]} {twice[1]} {twice[2]} {twice[3]}");
    rb.unmap(dev); // twice is done: rb can be copied into again
    var enc2 = dev.encoder();
    enc2.compute_pass(|pass| {
        pass.set_pipeline(clear);
        pass.set_bind_group(0, cgroup);
        pass.dispatch(1);
        pass.set_pipeline(deposit);
        pass.set_bind_group(0, dgroup);
        pass.dispatch(4);
    });
    enc2.copy_buffer(bins, 0, rb, 0, 16);
    queue.submit(enc2.finish());
    let once = gpu::u32s(rb.map_read(dev));
    println(f"{once[0]} {once[1]} {once[2]} {once[3]}");
    Ok(())
}
```
```out
layouts: 2 and 1
128 128 128 128
64 64 64 64
```

The dispatches of one pass (the clear, then the deposit, above) run
one after the other, each seeing the writes of the ones before
(`gpu#ordering`).

## A compute simulation

The shape of a simulation step loop (particles, a fluid, a lattice):
the state in two buffers, read from one and written into the other
(`gpu#ping-pong`); what changes from step to step in a buffer the steps
index (`gpu#per-step-parameters`); every step a dispatch of one pass
(`gpu#ordering`); and a readback that checks it: read the state
(`map_read`, or `map_read_copy_in` to keep it) and compare it with a
CPU reference computed independently, element by element, not only a
sum or a range (`guide testing#a-check-must-be-able-to-fail`), as both
examples below do.

## Ping-pong

Ping-pong buffers: a step that reads its neighbours' old values cannot
write them in place, since an invocation could read one that another
has already written. So the state lives in two buffers. Step `s` reads `bufs[s % 2]` and
writes `bufs[1 - s % 2]`, through one of two bind groups made once
(`groups[k]` binds `bufs[k]` for reading and the other for writing),
picked by the step's parity. Every step is a dispatch of one compute
pass: each runs after the one before and sees all it wrote
(`gpu#ordering`), so nothing goes between them, no submit, no wait.
After `n` steps the state is in the buffer the last step wrote,
`bufs[n % 2]` (with `n` even, the one it started in). A kernel whose
invocations each read and write only their own element needs one
buffer.

```vole
use std::gpu;
use std::gpu::BufferUsage;

const N: i64 = 256;
const STEPS: i64 = 25;

// next[i] = (cur[i - 1] + cur[i] + cur[i + 1]) % 251, on a ring of N
const BLUR: [u8] = """
    @group(0) @binding(0) var<storage, read> cur: array<u32>;
    @group(0) @binding(1) var<storage, read_write> next: array<u32>;
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        let n = arrayLength(&cur);
        let i = id.x;
        if (i >= n) { return; }
        next[i] = (cur[(i + n - 1u) % n] + cur[i] + cur[(i + 1u) % n]) % 251u;
    }
    """;

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let pipe = dev.compute_pipeline(dev.shader_wgsl(BLUR)?, "main")?;
    var start: Vec<u32> = Vec::new_in(gpa);
    for i in 0..N { start.push((i * i % 97) as u32); }
    let usage = BufferUsage::STORAGE | BufferUsage::COPY_SRC;
    let bufs = [dev.buffer_init(gpu::bytes_of_u32(start.as_slice()), usage), dev.buffer(N * 4, usage)];
    let layout = pipe.bind_layout(0);
    let groups = [ // groups[k] reads bufs[k], writes bufs[1 - k]
        dev.bind_group(layout, [gpu::bind(0, bufs[0]), gpu::bind(1, bufs[1])][..]),
        dev.bind_group(layout, [gpu::bind(0, bufs[1]), gpu::bind(1, bufs[0])][..]),
    ];
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        for s in 0..STEPS {
            pass.set_bind_group(0, groups[s % 2]); // the parity
            pass.dispatch((N + 63) / 64); // reads what the last one wrote
        }
    });
    let last = STEPS % 2; // step STEPS - 1 wrote bufs[1 - (STEPS - 1) % 2]
    var rb = dev.buffer(N * 4, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    enc.copy_buffer(bufs[last], 0, rb, 0, N * 4);
    queue.submit(enc.finish());
    // the same steps on the CPU: the reference
    var cur = start.clone();
    var next = start.clone();
    for _ in 0..STEPS {
        for i in 0..N {
            next[i] = (cur[(i + N - 1) % N] + cur[i] + cur[(i + 1) % N]) % 251;
        }
        std::swap(&cur, &next);
    }
    let got = gpu::u32s(rb.map_read(dev));
    var differ = 0;
    for i in 0..N {
        if got[i] != cur[i] { differ += 1; }
    }
    println(f"{STEPS} steps in one pass, the state in bufs[{last}], {differ} of {N} differ from the CPU");
    Ok(())
}
```
```out
25 steps in one pass, the state in bufs[1], 0 of 256 differ from the CPU
```

## Per-step parameters

Per-step parameters (a time, a force, a step number) cannot be one
uniform written each step: `queue.write_buffer` lands before the next
submit's commands (`gpu#ordering`), so the steps recorded in one
encoder all see the uniform's last value, and a write per step works
only with a submit per step. The ways to give each step its own
values, and what each costs:

| way | cost |
|---|---|
| `write_buffer`, then a submit, each step | a submit a step (tens of microseconds, and a staging copy while the GPU is busy): fine for a few steps a frame, seconds of overhead at 40,000 |
| a uniform range a step: one buffer of `steps * dev.align_uniform(size)` bytes, written once, and a bind group a step binding its range (`gpu::bind_range(b, ubuf, s * stride, size)`) | 256 bytes and a bind group a step, made before the pass: for a count of steps known in advance |
| a storage buffer of the parameters, `array<P>`, indexed by a step number the GPU counts: a kernel of one invocation adds 1 after each step (below) | one more dispatch a step (microseconds) and two bind groups whatever the count; an earlier kernel may compute the parameters too |

```vole
use std::gpu;
use std::gpu::BufferUsage;

const N: i64 = 64;
const STEPS: i64 = 10;

// next[i] = (cur[i - 1] + cur[i + 1] + params[step]) % 251; ctl[0] is the step
const STEP: [u8] = """
    @group(0) @binding(0) var<storage, read> ctl: array<u32>;
    @group(0) @binding(1) var<storage, read> params: array<u32>;
    @group(0) @binding(2) var<storage, read> cur: array<u32>;
    @group(0) @binding(3) var<storage, read_write> next: array<u32>;
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        let n = arrayLength(&cur);
        let i = id.x;
        if (i >= n) { return; }
        next[i] = (cur[(i + n - 1u) % n] + cur[(i + 1u) % n] + params[ctl[0]]) % 251u;
    }
    """;

// one invocation: the next step's number
const TICK: [u8] = """
    @group(0) @binding(0) var<storage, read_write> ctl: array<u32>;
    @compute @workgroup_size(1) fn main() { ctl[0] += 1u; }
    """;

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let step = dev.compute_pipeline(dev.shader_wgsl(STEP)?, "main")?;
    let tick = dev.compute_pipeline(dev.shader_wgsl(TICK)?, "main")?;
    var start: Vec<u32> = Vec::new_in(gpa);
    var params: Vec<u32> = Vec::new_in(gpa);
    for i in 0..N { start.push((i * i % 97) as u32); }
    for s in 0..STEPS { params.push((s * 7 % 11) as u32); } // any values, one a step
    let usage = BufferUsage::STORAGE | BufferUsage::COPY_SRC;
    let bufs = [dev.buffer_init(gpu::bytes_of_u32(start.as_slice()), usage), dev.buffer(N * 4, usage)];
    let ctl = dev.buffer_init(gpu::bytes_of_u32([0u32][..]), BufferUsage::STORAGE);
    let pbuf = dev.buffer_init(gpu::bytes_of_u32(params.as_slice()), BufferUsage::STORAGE);
    let l = step.bind_layout(0);
    let groups = [
        dev.bind_group(l, [gpu::bind(0, ctl), gpu::bind(1, pbuf), gpu::bind(2, bufs[0]), gpu::bind(3, bufs[1])][..]),
        dev.bind_group(l, [gpu::bind(0, ctl), gpu::bind(1, pbuf), gpu::bind(2, bufs[1]), gpu::bind(3, bufs[0])][..]),
    ];
    let tgroup = dev.bind_group(tick.bind_layout(0), [gpu::bind(0, ctl)][..]);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        for s in 0..STEPS {
            pass.set_pipeline(step);
            pass.set_bind_group(0, groups[s % 2]);
            pass.dispatch((N + 63) / 64);
            pass.set_pipeline(tick);
            pass.set_bind_group(0, tgroup);
            pass.dispatch(1);
        }
    });
    var rb = dev.buffer(N * 4, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    enc.copy_buffer(bufs[STEPS % 2], 0, rb, 0, N * 4);
    queue.submit(enc.finish());
    var cur = start.clone();
    var next = start.clone();
    for s in 0..STEPS {
        for i in 0..N {
            next[i] = (cur[(i + N - 1) % N] + cur[(i + 1) % N] + params[s]) % 251;
        }
        std::swap(&cur, &next);
    }
    let got = gpu::u32s(rb.map_read(dev));
    var differ = 0;
    for i in 0..N {
        if got[i] != cur[i] { differ += 1; }
    }
    println(f"{STEPS} steps, one submit, {differ} of {N} differ from the CPU");
    Ok(())
}
```
```out
10 steps, one submit, 0 of 64 differ from the CPU
```

## Timing GPU work

std::gpu has no timestamp queries (no GPU-side clock): time the work on
the CPU, around the submission and a wait for it to finish:

```vole
use std::gpu;

fn timed(dev: gpu::Device, queue: inout gpu::Queue, pipe: gpu::ComputePipeline,
    group: gpu::BindGroup, groups: i64) -> Result<f64, gpu::Error> {
    let t0 = std::time::monotonic_now();
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(groups);
    });
    queue.submit(enc.finish());
    queue.wait_idle()?; // until the GPU has finished
    Ok(std::time::monotonic_now().saturating_sub(t0).as_millis_f64())
}
```

- What it measures is wall time: encoding on the CPU, submission, the
  GPU's work and the wait's wake-up. For the GPU's share, make the work
  large (many steps in one submission) so the fixed cost (tens of
  microseconds) is small beside it, and say so when reporting.
- Run it a few times first (the first submission compiles and warms
  caches), then take the median of several runs, not one.
- This is one submission's latency. A rate (frames or steps a second)
  is throughput: submit N without waiting between them, `wait_idle`
  once, divide by N (`guide window#when-the-window-is-not-shown`).
- A frame loop's time is the time between frames: with vsync it is the
  display's rate, not the GPU's, and while the window is not shown a
  10 Hz timer's; time with `vsync: false` or headless.
- `map_read` and `dev.wait_idle()` wait too: a readback inside the timed
  region adds its copy.

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
- Names are never a problem (0.25.2): an identifier Metal keeps for
  itself (`quad`, `float4`, `half`, `kernel`, `INFINITY`, `M_PI_F`,
  `assert`, `class`, `this`, `new`, `device`, any C++ keyword) is
  renamed in the MSL (std::gpu::wgsl::msl's list), and WGSL's own
  predeclared names (`array`, `vec4f`, `bitcast`) may be shadowed; entry
  points keep their WGSL names for `compute_pipeline` and `RenderDesc`.
  What is left to avoid is WGSL's keywords themselves (`fn`, `let`,
  `var`, `loop`, `if`, `struct`, ...) and `_` alone: `wgsl.syntax`.
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
| `gpu.layout` | a bind group that does not match the pipeline's layout (the message names the layout's bindings) | make it from `pipe.bind_layout(i)`, one entry per binding the pipeline's entry points use |
| `gpu.pipeline` | a draw or dispatch without a pipeline or a bind group it uses | `pass.set_pipeline`, `pass.set_bind_group` |
| `gpu.format` | a format that does not fit: target, view, storage, shader kind | the pipeline's target format |
| `gpu.limits` | a size or count above `dev.limits()` (what a shader asks, its workgroup size or bindings, is an `Err` instead); the message names the limit as `dev.limits().NAME` | smaller, or a larger `max_buffer_size` at `adapter.device(lim)` |
| `gpu.unwritten` | a submit reads a uniform buffer nothing wrote (0.25.2.2) | `queue.write_buffer` before the submit, or `dev.buffer_init` |
| `gpu.state` | a buffer written while mapped for reading (a copy into it or `write_buffer`: at the copy, or at `queue.submit` when recorded before `map_read`), or used while mapped for writing | `buf.unmap(dev)` when its view is done, or `map_read_copy_in` |
| `gpu.unsupported` | a capability the device lacks | check `dev.caps()` |

Surfaces (`inst.surface(dev, RawSurface::MetalLayer(layer))`,
`surf.configure(..)`, `surf.frame()?`, `frame.present(&queue)`) are
what std::window draws into; `RawSurface::Headless` gives frames without
a window (to check a window's pixels: `window#checking-the-pixels-headless`).
