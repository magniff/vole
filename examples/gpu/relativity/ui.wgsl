// The immediate-mode UI's draw list: one quad per solid shape or glyph,
// alpha-blended over the path-traced image. Solid quads sample texel 0 of
// the atlas, the white one; characters sample their glyph's coverage.

struct VIn {
    @location(0) pos: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) uv: vec2<f32>,
}
struct VOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
}
@group(0) @binding(0) var atlas: texture_2d<f32>;
@group(0) @binding(1) var samp: sampler;

@vertex fn vs(v: VIn) -> VOut {
    var o: VOut;
    o.pos = vec4<f32>(v.pos, 0.0, 1.0);
    o.color = v.color;
    o.uv = v.uv;
    return o;
}

@fragment fn fs(v: VOut) -> @location(0) vec4<f32> {
    let coverage = textureSampleLevel(atlas, samp, v.uv, 0.0).r;
    return vec4<f32>(v.color.rgb, v.color.a * coverage);
}
