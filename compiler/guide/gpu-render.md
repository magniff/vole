# GPU rendering: std::gpu (0.22; guide updated 0.25.4)

Drawing with std::gpu (`guide gpu` for the objects, compute, bind groups,
usages and formats, limits and contracts): a render pipeline
(`RenderDesc`) draws in a render pass (`enc.render_pass(PassDesc, |pass|
..)`) into a texture or a window's frame, read back with
`enc.copy_texture_to_buffer`.

## Render to a texture

```vole
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, Reflection, ShaderSource, TextureUsage};

fn main(gpa: Gpa) -> Result<(), gpu::Error<Gpa>> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, mut queue) = inst.adapter(gpu::Power::High)?.device(gpu::Limits::default())?;
    let code = "#include <metal_stdlib>\nusing namespace metal;\nvertex float4 vs(uint v [[vertex_id]]) { float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) }; return float4(p[v], 0, 1); }\nfragment float4 fs() { return float4(1, 0.5, 0, 1); }\n";
    let mut refl = Reflection::new_in(gpa);
    refl.vertex("vs", "vs");
    refl.fragment("fs", "fs");
    let src = ShaderSource::msl(code, refl);
    let shader = dev.shader(&src)?;
    let desc = gpu::RenderDesc::new(&shader, "vs", "fs", Format::Rgba8Unorm);
    let pipe = dev.render_pipeline(desc)?;
    let tex = dev.texture(8, 8, Format::Rgba8Unorm,
        TextureUsage::RENDER_ATTACHMENT | TextureUsage::COPY_SRC);
    let view = tex.view();
    let mut out = dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    let mut enc = dev.encoder();
    enc.render_pass(PassDesc::color(&view, gpu::Color::black(), gpu::Load::Clear),
        |pass| { // cleared to black, then drawn
        pass.set_pipeline(&pipe);
        pass.draw(0..3, 0..1); // a triangle over the whole target
    });
    enc.copy_texture_to_buffer(&tex, &out, 256); // rows 256 bytes apart
    queue.submit(enc.finish());
    let px = out.map_read(&dev);
    println("{} {} {} {}", px[0], px[1], px[2], px[3]);
    Ok(())
}
```
```out
255 128 0 255
```

## A textured quad

A vertex buffer of several attributes (`VertexLayout`: the stride, then
each `@location(n)` with its format and offset), a one-channel texture
written from the CPU (`queue.write_texture(&tex, bytes, bytes_per_row)`,
the whole of it; a part or another layer with `write_texture_region(..,
x, y, w, h, layer)`, as `copy_texture_to_buffer_region` reads one back),
a sampler, and both bound beside each other: `gpu::bind_texture`,
`gpu::bind_sampler`. A fragment shader samples with `textureSample`, or
`textureSampleLevel(t, s, uv, 0.0)` where it must name the level (a
texture of one mip level, or code outside uniform control flow); an
`R8Unorm` texel reads as `vec4<f32>(r, 0, 0, 1)`, r in 0..1.

```vole
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, SamplerDesc, TextureUsage, VertexFormat, VertexLayout};

embed wgsl QUAD {
    struct VOut { @builtin(position) pos: vec4<f32>, @location(0) uv: vec2<f32> }
    @group(0) @binding(0) var t: texture_2d<f32>;
    @group(0) @binding(1) var s: sampler;
    @vertex fn vs(@location(0) pos: vec2<f32>, @location(1) uv: vec2<f32>) -> VOut {
        return VOut(vec4<f32>(pos, 0.0, 1.0), uv);
    }
    @fragment fn fs(v: VOut) -> @location(0) vec4<f32> {
        let r = textureSampleLevel(t, s, v.uv, 0.0).r;
        return vec4<f32>(r, r, r, 1.0);
    }
}

fn main(gpa: Gpa) -> Result<(), gpu::Error<Gpa>> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, mut queue) = inst.adapter(gpu::Power::High)?.device(gpu::Limits::default())?;
    let shader = dev.shader_wgsl(QUAD.src)?;
    let mut desc = gpu::RenderDesc::new(&shader, QUAD.vs, QUAD.fs, Format::Rgba8Unorm);
    let mut layout = VertexLayout::new(16, gpu::StepMode::Vertex); // x, y, u, v: four f32s a vertex
    layout.attribute(0, VertexFormat::Float32x2, 0);
    layout.attribute(1, VertexFormat::Float32x2, 8);
    desc.vertex_buffer(layout);
    let pipe = dev.render_pipeline(desc)?;
    // two triangles over the target; uv (0, 0) at its top left
    let quad: [f32; 24] = [
        -1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, -1.0, -1.0, 0.0, 1.0,
        -1.0, -1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, -1.0, 1.0, 1.0,
    ];
    let vb = dev.buffer_init(gpu::bytes_of_f32(&quad[..]), BufferUsage::VERTEX);
    // a 2 x 2 R8Unorm texture, a byte a texel, rows of 2 bytes
    let image = dev.texture(2, 2, Format::R8Unorm,
        TextureUsage::TEXTURE_BINDING | TextureUsage::COPY_DST); // TEXTURE_BINDING | COPY_DST
    let texels: [u8; 4] = [0, 64, 128, 255];
    queue.write_texture(&image, &texels[..], 2);
    let sampler = dev.sampler(SamplerDesc::nearest());
    let group = dev.bind_group(pipe.bind_layout(0),
        &[gpu::bind_texture(0, &image.view()), gpu::bind_sampler(1, &sampler)][..]);
    let target = dev.texture(4, 4, Format::Rgba8Unorm,
        TextureUsage::RENDER_ATTACHMENT | TextureUsage::COPY_SRC);
    let mut out = dev.buffer(256 * 4, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    let mut enc = dev.encoder();
    enc.render_pass(PassDesc::color(&target.view(), gpu::Color::black(), gpu::Load::Clear), |pass| {
        pass.set_pipeline(&pipe);
        pass.set_bind_group(0, &group);
        pass.set_vertex_buffer(0, &vb, 0);
        pass.draw(0..6, 0..1);
    });
    enc.copy_texture_to_buffer(&target, &out, 256);
    queue.submit(enc.finish());
    let px = out.map_read(&dev);
    // the red byte of the four corners: each texel covers 2 x 2 pixels
    println("{} {} {} {}", px[0], px[3 * 4], px[3 * 256], px[3 * 256 + 3 * 4]);
    Ok(())
}
```
```out
0 64 128 255
```

## Drawing over the image you just made

An overlay (a panel, a label, a cursor) is one more render pass into the
same target after the scene's passes and before `frame.present`: a
pass that keeps what is there instead of clearing it,
`PassDesc::color(&view, Color::black(), load: Load::Keep)`, and a pipeline that blends
over it, `desc.blend(Blend::alpha(), 0)` (source over destination, straight
alpha; `Blend::premultiplied()` for premultiplied colours). Everything
is a textured quad from one vertex buffer of position, colour and uv
(`VertexLayout::new(32, gpu::StepMode::Vertex)`: `Float32x2`, `Float32x4`, `Float32x2`), and
one `R8Unorm` atlas (`queue.write_texture`) holds the glyphs and a white
texel: a solid quad samples the white texel, a character its glyph, and
the fragment shader writes the colour with alpha times the coverage. A
string's width is its glyph count times the advance, less the last gap,
so text is measured before it is placed (centred, right-aligned). A
window's frame is `Bgra8Unorm`: the pipeline's format is the frame's.

```vole
use std::gpu;
use std::gpu::{Blend, BufferUsage, Color, Format, Load, PassDesc, SamplerDesc, TextureUsage, VertexFormat, VertexLayout};

embed wgsl UI {
    struct VIn {
        @location(0) pos: vec2<f32>, @location(1) color: vec4<f32>, @location(2) uv: vec2<f32>,
    }
    struct VOut {
        @builtin(position) pos: vec4<f32>, @location(0) color: vec4<f32>, @location(1) uv: vec2<f32>,
    }
    @group(0) @binding(0) var atlas: texture_2d<f32>;
    @group(0) @binding(1) var samp: sampler;
    @vertex fn vs(v: VIn) -> VOut {
        return VOut(vec4<f32>(v.pos, 0.0, 1.0), v.color, v.uv);
    }
    @fragment fn fs(v: VOut) -> @location(0) vec4<f32> {
        let coverage = textureSampleLevel(atlas, samp, v.uv, 0.0).r; // ink, or the white texel
        return vec4<f32>(v.color.rgb, v.color.a * coverage);
    }
}

// The atlas (R8Unorm, 12 x 5 texels, '#' is 255): the white texel at
// (0, 0) for solid quads, then 'H' and 'I', 3 x 5 each, at x 4 and 8.
static ART: [&str; 5] = [
    "#   # # ### ",
    "    # #  #  ",
    "    ###  #  ",
    "    # #  #  ",
    "    # # ### ",
];
const AW: f64 = 12.0;
const AH: f64 = 5.0;
const W: i64 = 16; // the target, in pixels
const H: i64 = 8;

// Pixels (x0, y0)-(x1, y1) showing atlas texels (u0, v0)-(u1, v1) (in
// 0..1) in colour c: two triangles of x, y, r, g, b, a, u, v.
fn quad(vs: &mut Vec<f32, Gpa>, x0: f64, y0: f64, x1: f64, y1: f64, uv: [f64; 4], c: [f32; 4]) {
    let (l, r) = (2.0 * x0 / W as f64 - 1.0, 2.0 * x1 / W as f64 - 1.0);
    let (t, b) = (1.0 - 2.0 * y0 / H as f64, 1.0 - 2.0 * y1 / H as f64);
    let corners = [
        [l, t, uv[0], uv[1]], [r, t, uv[2], uv[1]], [l, b, uv[0], uv[3]],
        [l, b, uv[0], uv[3]], [r, t, uv[2], uv[1]], [r, b, uv[2], uv[3]],
    ];
    for p in corners {
        vs.extend_from_slice(&[p[0] as f32, p[1] as f32, c[0], c[1], c[2], c[3], p[2] as f32,
            p[3] as f32][..]);
    }
}

// The width of s in pixels: 4 a glyph (3 of ink, 1 of space), less the last space.
fn text_width(s: &[u8]) -> f64 {
    if s.len() == 0 { 0.0 } else { (s.len() * 4 - 1) as f64 }
}

// One quad a glyph from (x, y), the top left; its cell from the byte.
fn text(vs: &mut Vec<f32, Gpa>, x: f64, y: f64, s: &[u8], c: [f32; 4]) {
    let mut cx = x;
    for &ch in s {
        let u = if ch == b'H' { 4.0 } else { 8.0 }; // a real font: a table of cells
        quad(vs, cx, y, cx + 3.0, y + 5.0, [u / AW, 0.0, (u + 3.0) / AW, 1.0], c);
        cx += 4.0;
    }
}

fn main(gpa: Gpa) -> Result<(), gpu::Error<Gpa>> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, mut queue) = inst.adapter(gpu::Power::High)?.device(gpu::Limits::default())?;
    let target = dev.texture(W, H, Format::Rgba8Unorm,
        TextureUsage::RENDER_ATTACHMENT | TextureUsage::COPY_SRC);
    let view = target.view();
    // the image you just made: here a pass that clears it to blue
    let mut enc = dev.encoder();
    enc.render_pass(PassDesc::color(&view, clear: Color::rgba(0.0, 0.0, 1.0, 1.0),
        load: Load::Clear), |_| {});
    queue.submit(enc.finish());

    // the overlay: a blended pipeline of position, colour and uv
    let shader = dev.shader_wgsl(UI.src)?;
    let mut desc = gpu::RenderDesc::new(&shader, UI.vs, UI.fs, Format::Rgba8Unorm); // a frame: Bgra8Unorm
    let mut layout = VertexLayout::new(32, gpu::StepMode::Vertex); // 8 f32s a vertex
    layout.attribute(0, VertexFormat::Float32x2, 0); // x, y
    layout.attribute(1, VertexFormat::Float32x4, 8); // r, g, b, a
    layout.attribute(2, VertexFormat::Float32x2, 24); // u, v
    desc.vertex_buffer(layout);
    desc.blend(Blend::alpha(), 0); // source over what is there
    let pipe = dev.render_pipeline(desc)?;
    let mut texels: Vec<u8, Gpa> = Vec::new_in(gpa);
    for row in ART {
        for &ch in row.as_bytes() {
            texels.push(if ch == b'#' { 255 } else { 0 });
        }
    }
    let atlas = dev.texture(12, 5, Format::R8Unorm,
        TextureUsage::TEXTURE_BINDING | TextureUsage::COPY_DST); // TEXTURE_BINDING | COPY_DST
    queue.write_texture(&atlas, texels.as_slice(), 12); // rows of 12 bytes
    let sampler = dev.sampler(SamplerDesc::nearest());
    let group = dev.bind_group(pipe.bind_layout(0),
        &[gpu::bind_texture(0, &atlas.view()), gpu::bind_sampler(1, &sampler)][..]);

    // the draw list: a half-dark box, then "HI" measured and centred in it
    let mut verts: Vec<f32, Gpa> = Vec::new_in(gpa);
    let white = [0.5 / AW, 0.5 / AH, 0.5 / AW, 0.5 / AH];
    quad(&mut verts, 1.0, 1.0, 10.0, 8.0, white, [0.0, 0.0, 0.0, 0.5]);
    let label = "HI";
    text(&mut verts, 1.0 + (9.0 - text_width(label.as_bytes())) / 2.0, 2.0, label.as_bytes(), [1.0, 1.0, 0.0, 1.0]);
    let vb = dev.buffer_init(gpu::bytes_of_f32(verts.as_slice()), BufferUsage::VERTEX);
    let count = verts.len() / 8;
    let mut out = dev.buffer(256 * H, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    let mut enc2 = dev.encoder();
    enc2.render_pass(PassDesc::color(&view, Color::black(), load: Load::Keep),
        |pass| { // kept, not cleared
        pass.set_pipeline(&pipe);
        pass.set_bind_group(0, &group);
        pass.set_vertex_buffer(0, &vb, 0);
        pass.draw(0..count as i64, 0..1);
    });
    enc2.copy_texture_to_buffer(&target, &out, 256);
    queue.submit(enc2.finish());
    let px = out.map_read(&dev);
    // a pixel a character: '#' the text, 'o' the box, '.' the image
    for y in 0..H as usize {
        let mut line: [u8; 16] = [0; 16];
        for x in 0..W as usize {
            let p = y * 256 + x * 4;
            line[x] = if px[p] > 200 { b'#' } else if px[p + 2] > 200 { b'.' } else { b'o' };
        }
        println("{}", str::from_utf8(&line[..]).unwrap());
    }
    println("box {}, image {}", px[256 + 4 + 2], px[256 + 14 * 4 + 2]); // blue, half and whole
    Ok(())
}
```
```out
................
.ooooooooo......
.o#o#o###o......
.o#o#oo#oo......
.o###oo#oo......
.o#o#oo#oo......
.o#o#o###o......
.ooooooooo......
box 128, image 255
```

A whole one: examples/gpu/pathtrace (`ui_render.vl`: the pipeline and
the pass; `font.vl`: a 5 x 7 font of 95 glyphs baked into a 128 x 128
atlas; `ui.wgsl`; `ui.vl`'s `quad`, `text`, `text_width`, with
clipping). Its `--headless --ui` draws the panel over the final frame
and writes a PPM (`guide window#checking-the-pixels-headless`).

## Multiple render targets

One pass can write several textures at once, a G-buffer: the pass
names a color attachment for each (`PassDesc::color(&a, clear,
load).with_color(&b, clear, load)`,
at most 8), the pipeline a target of the same format for each, in the
same order (`RenderDesc::new`'s format is target 0, then
`desc.target(format)`), and the fragment shader returns a struct whose
`@location(i)` member is written into attachment i.

```vole
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, TextureUsage};

embed wgsl GBUFFER {
    struct G {
        @location(0) albedo: vec4<f32>,
        @location(1) normal: vec4<f32>,
        @location(2) depth: f32,
    }
    @vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
        var p = vec2<f32>(-1.0, -1.0);
        if (i == 1u) { p = vec2<f32>(3.0, -1.0); }
        if (i == 2u) { p = vec2<f32>(-1.0, 3.0); }
        return vec4<f32>(p, 0.25, 1.0);
    }
    @fragment fn fs(@builtin(position) pos: vec4<f32>) -> G {
        return G(vec4<f32>(1.0, 0.5, 0.0, 1.0), vec4<f32>(0.0, 0.0, 1.0, 1.0), pos.z);
    }
}

fn main(gpa: Gpa) -> Result<(), gpu::Error<Gpa>> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, mut queue) = inst.adapter(gpu::Power::High)?.device(gpu::Limits::default())?;
    let shader = dev.shader_wgsl(GBUFFER.src)?;
    let mut desc = gpu::RenderDesc::new(&shader, GBUFFER.vs, GBUFFER.fs, Format::Rgba8Unorm); // target 0
    desc.target(Format::Rgba8Unorm); // target 1
    desc.target(Format::R32Float); // target 2
    let pipe = dev.render_pipeline(desc)?;
    let usage = TextureUsage::RENDER_ATTACHMENT | TextureUsage::COPY_SRC;
    let albedo = dev.texture(8, 8, Format::Rgba8Unorm, usage);
    let normal = dev.texture(8, 8, Format::Rgba8Unorm, usage);
    let depth = dev.texture(8, 8, Format::R32Float, usage);
    let (av, nv, dv) = (albedo.view(), normal.view(), depth.view());
    let mut outs = [
        dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST),
        dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST),
        dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST),
    ];
    let mut enc = dev.encoder();
    enc.render_pass(PassDesc::color(&av, gpu::Color::black(), gpu::Load::Clear).with_color(&nv,
        gpu::Color::black(), gpu::Load::Clear).with_color(&dv, gpu::Color::black(),
        gpu::Load::Clear), |pass| {
        pass.set_pipeline(&pipe);
        pass.draw(0..3, 0..1); // one draw writes all three
    });
    enc.copy_texture_to_buffer(&albedo, &outs[0], 256);
    enc.copy_texture_to_buffer(&normal, &outs[1], 256);
    enc.copy_texture_to_buffer(&depth, &outs[2], 256);
    queue.submit(enc.finish());
    let a = outs[0].map_read_copy_in(&dev, gpa);
    let n = outs[1].map_read_copy_in(&dev, gpa);
    let d = gpu::f32s(outs[2].map_read(&dev));
    println("albedo {} {} {}, normal {} {} {}, depth {}", a[0], a[1], a[2], n[0], n[1], n[2], d[0]);
    Ok(())
}
```
```out
albedo 255 128 0, normal 0 0 255, depth 0.25
```

The pass's pipelines must fit it: `pass.set_pipeline` checks that the
pipeline has as many color targets as the pass has color attachments,
each of its attachment's format (`gpu.format`, naming the counts or the
index), and a depth state only where the pass has a depth attachment.

## Depth-only passes

A shadow map is drawn with no color at all: `PassDesc::depth_only(&view, 1.0, true)`
(cleared to 1.0 and stored, to be read afterwards) and a pipeline with
no fragment stage and no color target, `RenderDesc::depth_only(&shader,
"vs", Format::Depth32Float, Compare::Less)` (a test that writes). The shader
needs only the vertex entry. The depth texture is then read by the next
pass as a `texture_depth_2d` (`textureLoad`, or `textureSampleCompare`
with a comparison sampler); it needs `TEXTURE_BINDING` for that.

```vole
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, TextureUsage, VertexFormat, VertexLayout};

embed wgsl SHADOW {
    @vertex fn vs(@location(0) p: vec3<f32>) -> @builtin(position) vec4<f32> {
        return vec4<f32>(p, 1.0);
    }
}

fn main(gpa: Gpa) -> Result<(), gpu::Error<Gpa>> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, mut queue) = inst.adapter(gpu::Power::High)?.device(gpu::Limits::default())?;
    let shader = dev.shader_wgsl(SHADOW.src)?;
    let mut desc = gpu::RenderDesc::depth_only(&shader, SHADOW.vs, Format::Depth32Float,
        gpu::Compare::Less);
    let mut layout = VertexLayout::new(12, gpu::StepMode::Vertex);
    layout.attribute(0, VertexFormat::Float32x3, 0);
    desc.vertex_buffer(layout);
    let pipe = dev.render_pipeline(desc)?;
    // one triangle over the left half of the map, at depth 0.25
    let tri: [f32; 9] = [-1.0, -1.0, 0.25, 0.0, -1.0, 0.25, -1.0, 3.0, 0.25];
    let vb = dev.buffer_init(gpu::bytes_of_f32(&tri[..]), BufferUsage::VERTEX);
    let map = dev.texture(8, 8, Format::Depth32Float,
        TextureUsage::RENDER_ATTACHMENT | TextureUsage::TEXTURE_BINDING | TextureUsage::COPY_SRC);
    let view = map.view();
    let mut out = dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    let mut enc = dev.encoder();
    enc.render_pass(PassDesc::depth_only(&view, 1.0, true), |pass| {
        pass.set_pipeline(&pipe);
        pass.set_vertex_buffer(0, &vb, 0);
        pass.draw(0..3, 0..1);
    });
    enc.copy_texture_to_buffer(&map, &out, 256);
    queue.submit(enc.finish());
    let d = gpu::f32s(out.map_read(&dev));
    println("left {}, right {}", d[0], d[7]); // the right half keeps the clear value
    Ok(())
}
```
```out
left 0.25, right 1
```

