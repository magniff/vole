struct Material {
    albedo: vec4<f32>,
    params: vec4<f32>,
    absorption: vec4<f32>,
}
struct Params {
    eye: vec4<f32>,
    target: vec4<f32>,
    dims: vec4<f32>,
    config: vec4<f32>,
    flags: vec4<f32>,
    env: vec4<f32>,
    light_pos: vec4<f32>,
    light_color: vec4<f32>,
    light_size: vec4<f32>,
    materials: array<Material, 4>,
    // the scene and the fog's scattering albedo (used by the tracer)
    fog: vec4<f32>,
}
struct Surface {
    normal: vec4<f32>,
    albedo: vec4<f32>,
    info: vec4<f32>,
}
@group(0) @binding(0) var<uniform> u: Params;
@group(0) @binding(1) var<storage, read> accum: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read> gbuffer: array<Surface>;
@group(0) @binding(3) var<storage, read> rays: array<vec4<f32>>;
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
fn tone(color: vec3<f32>) -> vec3<f32> {
    let exposed = max(color * u.config.w, vec3<f32>(0.0));
    let mapped = exposed / (exposed + vec3<f32>(1.0));
    return pow(mapped, vec3<f32>(1.0 / 2.2));
}
fn heat(t: f32) -> vec3<f32> {
    let x = clamp(t, 0.0, 1.0);
    return vec3<f32>(clamp(2.0 * x, 0.0, 1.0),
        clamp(2.0 - 2.0 * abs(x - 0.5), 0.0, 1.0), clamp(1.0 - 2.0 * x, 0.0, 1.0));
}
fn project(p: vec3<f32>) -> vec3<f32> {
    let forward = normalize(u.target.xyz - u.eye.xyz);
    let right = normalize(cross(forward, vec3<f32>(0.0, 1.0, 0.0)));
    let up = cross(right, forward);
    let relative = p - u.eye.xyz;
    let depth = dot(relative, forward);
    let aspect = u.dims.x / u.dims.y;
    let x = dot(relative, right) / max(0.0001, depth * aspect * u.config.x);
    let y = dot(relative, up) / max(0.0001, depth * u.config.x);
    return vec3<f32>((x * 0.5 + 0.5) * u.dims.x, (0.5 - y * 0.5) * u.dims.y, depth);
}
fn segment_distance(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let ab = b - a;
    let t = clamp(dot(p - a, ab) / max(0.0001, dot(ab, ab)), 0.0, 1.0);
    return length(p - (a + ab * t));
}
@fragment fn fs(v: Vertex) -> @location(0) vec4<f32> {
    let width = u32(u.dims.x);
    let height = u32(u.dims.y);
    let x = min(width - 1u, u32(v.uv.x * u.dims.x));
    let y = min(height - 1u, u32(v.uv.y * u.dims.y));
    let index = y * width + x;
    let count = max(1.0, u.dims.z + 1.0);
    let average = accum[index * 3u].xyz / count;
    var linear = average;
    if u.env.w > 0.5 && v.uv.x < 0.5 { linear = accum[index * 3u + 2u].xyz; }
    var color = tone(linear);
    if u.env.w > 0.5 && abs(v.uv.x - 0.5) * u.dims.x < 0.7 {
        color = vec3<f32>(0.8, 0.9, 1.0);
    }
    let mode = u32(u.flags.x + 0.5);
    if mode == 1u { color = gbuffer[index].normal.xyz * 0.5 + vec3<f32>(0.5); }
    if mode == 2u { color = tone(gbuffer[index].albedo.xyz); }
    if mode == 3u { color = heat(1.0 - exp(-gbuffer[index].normal.w * 0.075)); }
    if mode == 4u { color = heat(gbuffer[index].info.x * 0.012); }
    if mode == 5u {
        let id = u32(gbuffer[index].albedo.w + 0.5);
        color = heat(fract(f32(id) * 0.61803398875));
    }
    if mode == 6u { color = heat(gbuffer[index].info.y / 6.0); }
    if mode == 7u {
        let mean = max(0.0001, dot(average, vec3<f32>(0.3333333333)));
        let m2 = accum[index * 3u + 1u].x / count;
        let standard_error = sqrt(max(0.0, m2 - mean * mean) / max(1.0, count - 1.0));
        color = heat(standard_error / max(0.03, mean));
    }
    let pixel = vec2<f32>(f32(x), f32(y));
    if mode == 8u {
        let nodes = u32(rays[17].x);
        for (var i: u32 = 0u; i < 14u; i += 1u) {
            if i + 1u < nodes {
                let a = project(rays[i].xyz);
                let b = project(rays[i + 1u].xyz);
                if a.z > 0.0 && b.z > 0.0 && segment_distance(pixel, a.xy, b.xy) < 1.6 {
                    let event = rays[i + 1u].w;
                    var ray_color = vec3<f32>(1.0, 0.85, 0.15);
                    if event == 2.0 { ray_color = vec3<f32>(0.1, 0.9, 1.0); }
                    if event == 3.0 { ray_color = vec3<f32>(1.0, 0.2, 0.85); }
                    if event == 4.0 { ray_color = vec3<f32>(1.0, 0.45, 0.1); }
                    color = ray_color;
                }
            }
        }
        let selected = u.light_size.zw * u.dims.xy;
        if abs(pixel.x - selected.x) < 0.8 || abs(pixel.y - selected.y) < 0.8 {
            if length(pixel - selected) < 8.0 { color = vec3<f32>(1.0); }
        }
    }
    return vec4<f32>(color, 1.0);
}
