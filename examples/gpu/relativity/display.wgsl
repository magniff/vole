// Tone-map and upscale the film buffer into the surface. The film is traced
// at logical resolution (the surface's physical pixels divided by the display
// scale), so a Retina frame is one bilinear fetch per output pixel and the
// village shader runs once per point, not once per pixel.

struct Params {
    eye: vec4<f32>,
    forward: vec4<f32>,
    right: vec4<f32>,
    up: vec4<f32>,
    beta: vec4<f32>,
    gamma: vec4<f32>,
    effects: vec4<f32>,
    sun: vec4<f32>,
    misc: vec4<f32>,
};
@group(0) @binding(0) var<uniform> u: Params;
@group(0) @binding(1) var<storage, read> film: array<vec4<f32>>;

struct VOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex fn vs(@builtin(vertex_index) i: u32) -> VOut {
    let x = f32((i << 1u) & 2u);
    let y = f32(i & 2u);
    var o: VOut;
    o.pos = vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    o.uv = vec2<f32>(x, y);
    return o;
}

fn tap(p: vec2<f32>, size: vec2<f32>) -> vec3<f32> {
    let q = clamp(vec2<i32>(p), vec2<i32>(0), vec2<i32>(size) - vec2<i32>(1));
    return film[u32(q.y) * u32(size.x) + u32(q.x)].rgb;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@fragment fn fs(v: VOut) -> @location(0) vec4<f32> {
    let size = vec2<f32>(u.misc.y, u.misc.z);
    let p = v.uv * size - vec2<f32>(0.5);
    let base = floor(p);
    let f = fract(p);
    let c00 = tap(base, size);
    let c10 = tap(base + vec2<f32>(1.0, 0.0), size);
    let c01 = tap(base + vec2<f32>(0.0, 1.0), size);
    let c11 = tap(base + vec2<f32>(1.0, 1.0), size);
    let linear = mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
    let mapped = aces(max(linear * u.up.w, vec3<f32>(0.0)));
    return vec4<f32>(pow(mapped, vec3<f32>(1.0 / 2.2)), 1.0);
}
