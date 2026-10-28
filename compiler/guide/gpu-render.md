# GPU rendering: std::gpu (0.22; guide updated 0.25.2.2)

Drawing with std::gpu (`guide gpu` for the objects, compute, bind groups,
usages and formats, limits and contracts): a render pipeline
(`RenderDesc`) draws in a render pass (`enc.render_pass(PassDesc, |pass|
..)`) into a texture or a window's frame, read back with
`enc.copy_texture_to_buffer`.

## Render to a texture

```vole
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

## A textured quad

A vertex buffer of several attributes (`VertexLayout`: the stride, then
each `@location(n)` with its format and offset), a one-channel texture
written from the CPU (`queue.write_texture(tex, bytes, bytes_per_row)`),
a sampler, and both bound beside each other: `gpu::bind_texture`,
`gpu::bind_sampler`. A fragment shader samples with `textureSample`, or
`textureSampleLevel(t, s, uv, 0.0)` where it must name the level (a
texture of one mip level, or code outside uniform control flow); an
`R8Unorm` texel reads as `vec4<f32>(r, 0, 0, 1)`, r in 0..1.

```vole
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, SamplerDesc, TextureUsage, VertexFormat, VertexLayout};

const QUAD: [u8] = "struct VOut { @builtin(position) pos: vec4<f32>, @location(0) uv: vec2<f32> }\n\
    @group(0) @binding(0) var t: texture_2d<f32>;\n\
    @group(0) @binding(1) var s: sampler;\n\
    @vertex fn vs(@location(0) pos: vec2<f32>, @location(1) uv: vec2<f32>) -> VOut {\n\
    return VOut(vec4<f32>(pos, 0.0, 1.0), uv);\n\
    }\n\
    @fragment fn fs(v: VOut) -> @location(0) vec4<f32> {\n\
    let r = textureSampleLevel(t, s, v.uv, 0.0).r;\n\
    return vec4<f32>(r, r, r, 1.0);\n\
    }";

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let shader = dev.shader_wgsl(QUAD)?;
    var desc = gpu::RenderDesc::new(shader, "vs", "fs", Format::Rgba8Unorm);
    var layout = VertexLayout::new(16); // x, y, u, v: four f32s a vertex
    layout.attribute(0, VertexFormat::Float32x2, 0);
    layout.attribute(1, VertexFormat::Float32x2, 8);
    desc.vertex_buffer(layout);
    let pipe = dev.render_pipeline(desc)?;
    // two triangles over the target; uv (0, 0) at its top left
    let quad: [f32; 24] = [
        -1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0, -1.0, -1.0, 0.0, 1.0,
        -1.0, -1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, -1.0, 1.0, 1.0,
    ];
    let vb = dev.buffer_init(gpu::bytes_of_f32(quad[..]), BufferUsage::VERTEX);
    // a 2 x 2 R8Unorm texture, a byte a texel, rows of 2 bytes
    let image = dev.texture(2, 2, Format::R8Unorm); // TEXTURE_BINDING | COPY_DST
    let texels: [u8; 4] = [0, 64, 128, 255];
    queue.write_texture(image, texels[..], 2);
    let sampler = dev.sampler(SamplerDesc::nearest());
    let group = dev.bind_group(pipe.bind_layout(0),
        [gpu::bind_texture(0, image.view()), gpu::bind_sampler(1, sampler)][..]);
    let target = dev.texture(4, 4, Format::Rgba8Unorm,
        usage: TextureUsage::RENDER_ATTACHMENT | TextureUsage::COPY_SRC);
    var out = dev.buffer(256 * 4, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    var enc = dev.encoder();
    enc.render_pass(PassDesc::color(target.view()), |pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.set_vertex_buffer(0, vb);
        pass.draw(0..6, 0..1);
    });
    enc.copy_texture_to_buffer(target, out, 256);
    queue.submit(enc.finish());
    let px = out.map_read(dev);
    // the red byte of the four corners: each texel covers 2 x 2 pixels
    println(f"{px[0]} {px[3 * 4]} {px[3 * 256]} {px[3 * 256 + 3 * 4]}");
    Ok(())
}
```
```out
0 64 128 255
```

## Multiple render targets

One pass can write several textures at once, a G-buffer: the pass
names a color attachment for each (`PassDesc::color(a).with_color(b)`,
at most 8), the pipeline a target of the same format for each, in the
same order (`RenderDesc::new`'s format is target 0, then
`desc.target(format)`), and the fragment shader returns a struct whose
`@location(i)` member is written into attachment i.

```vole
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, TextureUsage};

const GBUFFER: [u8] = "struct G {\n\
    @location(0) albedo: vec4<f32>,\n\
    @location(1) normal: vec4<f32>,\n\
    @location(2) depth: f32,\n\
    }\n\
    @vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {\n\
    var p = vec2<f32>(-1.0, -1.0);\n\
    if (i == 1u) { p = vec2<f32>(3.0, -1.0); }\n\
    if (i == 2u) { p = vec2<f32>(-1.0, 3.0); }\n\
    return vec4<f32>(p, 0.25, 1.0);\n\
    }\n\
    @fragment fn fs(@builtin(position) pos: vec4<f32>) -> G {\n\
    return G(vec4<f32>(1.0, 0.5, 0.0, 1.0), vec4<f32>(0.0, 0.0, 1.0, 1.0), pos.z);\n\
    }";

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let shader = dev.shader_wgsl(GBUFFER)?;
    var desc = gpu::RenderDesc::new(shader, "vs", "fs", Format::Rgba8Unorm); // target 0
    desc.target(Format::Rgba8Unorm); // target 1
    desc.target(Format::R32Float); // target 2
    let pipe = dev.render_pipeline(desc)?;
    let usage = TextureUsage::RENDER_ATTACHMENT | TextureUsage::COPY_SRC;
    let albedo = dev.texture(8, 8, Format::Rgba8Unorm, usage: usage);
    let normal = dev.texture(8, 8, Format::Rgba8Unorm, usage: usage);
    let depth = dev.texture(8, 8, Format::R32Float, usage: usage);
    let (av, nv, dv) = (albedo.view(), normal.view(), depth.view());
    var outs = [
        dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST),
        dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST),
        dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST),
    ];
    var enc = dev.encoder();
    enc.render_pass(PassDesc::color(av).with_color(nv).with_color(dv), |pass| {
        pass.set_pipeline(pipe);
        pass.draw(0..3, 0..1); // one draw writes all three
    });
    enc.copy_texture_to_buffer(albedo, outs[0], 256);
    enc.copy_texture_to_buffer(normal, outs[1], 256);
    enc.copy_texture_to_buffer(depth, outs[2], 256);
    queue.submit(enc.finish());
    let a = outs[0].map_read_copy_in(dev, gpa);
    let n = outs[1].map_read_copy_in(dev, gpa);
    let d = gpu::f32s(outs[2].map_read(dev));
    println(f"albedo {a[0]} {a[1]} {a[2]}, normal {n[0]} {n[1]} {n[2]}, depth {d[0]}");
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

A shadow map is drawn with no color at all: `PassDesc::depth_only(view)`
(cleared to 1.0 and stored, to be read afterwards) and a pipeline with
no fragment stage and no color target, `RenderDesc::depth_only(shader,
"vs")` (a `Depth32Float` test, `Compare::Less`, that writes). The shader
needs only the vertex entry. The depth texture is then read by the next
pass as a `texture_depth_2d` (`textureLoad`, or `textureSampleCompare`
with a comparison sampler); it needs `TEXTURE_BINDING` for that.

```vole
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, TextureUsage, VertexFormat, VertexLayout};

const SHADOW: [u8] = "@vertex fn vs(@location(0) p: vec3<f32>) -> @builtin(position) vec4<f32> {\n\
    return vec4<f32>(p, 1.0);\n\
    }";

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let shader = dev.shader_wgsl(SHADOW)?;
    var desc = gpu::RenderDesc::depth_only(shader, "vs");
    var layout = VertexLayout::new(12);
    layout.attribute(0, VertexFormat::Float32x3, 0);
    desc.vertex_buffer(layout);
    let pipe = dev.render_pipeline(desc)?;
    // one triangle over the left half of the map, at depth 0.25
    let tri: [f32; 9] = [-1.0, -1.0, 0.25, 0.0, -1.0, 0.25, -1.0, 3.0, 0.25];
    let vb = dev.buffer_init(gpu::bytes_of_f32(tri[..]), BufferUsage::VERTEX);
    let map = dev.texture(8, 8, Format::Depth32Float,
        usage: TextureUsage::RENDER_ATTACHMENT | TextureUsage::TEXTURE_BINDING | TextureUsage::COPY_SRC);
    let view = map.view();
    var out = dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    var enc = dev.encoder();
    enc.render_pass(PassDesc::depth_only(view), |pass| {
        pass.set_pipeline(pipe);
        pass.set_vertex_buffer(0, vb);
        pass.draw(0..3, 0..1);
    });
    enc.copy_texture_to_buffer(map, out, 256);
    queue.submit(enc.finish());
    let d = gpu::f32s(out.map_read(dev));
    println(f"left {d[0]}, right {d[7]}"); // the right half keeps the clear value
    Ok(())
}
```
```out
left 0.25, right 1
```

