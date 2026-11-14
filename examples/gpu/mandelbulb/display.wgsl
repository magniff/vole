// Upscale the ray-marched film to the surface. The fractal is evaluated
// only at the film's resolution; this pass is one texture fetch per output
// pixel (bilinear when the governor has lowered that resolution).

@group(0) @binding(0) var film: texture_2d<f32>;
@group(0) @binding(1) var film_sampler: sampler;

struct Vertex {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex fn vs(@builtin(vertex_index) id: u32) -> Vertex {
    let x = f32((id << 1u) & 2u);
    let y = f32(id & 2u);
    var out: Vertex;
    out.pos = vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    out.uv = vec2<f32>(x, y);
    return out;
}

@fragment fn fs(v: Vertex) -> @location(0) vec4<f32> {
    return textureSampleLevel(film, film_sampler, v.uv, 0.0);
}
