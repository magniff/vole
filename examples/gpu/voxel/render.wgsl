struct Camera {
    eye: vec4<f32>, forward: vec4<f32>, right: vec4<f32>, up: vec4<f32>,
    params: vec4<f32>, sun: vec4<f32>, misc: vec4<f32>, brush: vec4<f32>, brush_params: vec4<f32>,
}
struct Vertex { pos: vec4<f32>, normal: vec4<f32>, color: vec4<f32> }
@group(0) @binding(0) var<uniform> cam: Camera;
@group(0) @binding(1) var<storage, read> vertices: array<Vertex>;
@group(0) @binding(2) var<storage, read> meta: array<u32>;
struct Out {
    @builtin(position) pos: vec4<f32>, @location(0) world: vec3<f32>,
    @location(1) normal: vec3<f32>, @location(2) color: vec3<f32>,
    @location(3) distance: f32, @location(4) bary: vec3<f32>,
    @location(5) uv: vec2<f32>, @location(6) kind: f32,
}
fn project(p: vec3<f32>) -> vec4<f32> {
    let relative = p - cam.eye.xyz;
    let depth = dot(relative, cam.forward.xyz);
    if depth <= 0.05 { return vec4<f32>(0.0, 0.0, 2.0, 1.0); }
    let x = dot(relative, cam.right.xyz) / (cam.params.x * cam.params.y);
    let y = dot(relative, cam.up.xyz) / cam.params.x;
    return vec4<f32>(x, y, depth * 1.00010001 - 0.100010001, depth);
}
@vertex fn vs(@builtin(vertex_index) id: u32) -> Out {
    var out: Out;
    if id >= meta[0] {
        out.pos = vec4<f32>(0.0, 0.0, 2.0, 1.0);
        out.world = vec3<f32>(0.0); out.normal = vec3<f32>(0,1,0);
        out.color = vec3<f32>(0.0); out.distance = 0.0; out.bary = vec3<f32>(0.0);
        out.uv = vec2<f32>(0.0); out.kind = 0.0;
        return out;
    }
    let v = vertices[id];
    out.pos = project(v.pos.xyz);
    out.world = v.pos.xyz;
    out.normal = v.normal.xyz;
    out.color = v.color.xyz;
    out.distance = length(v.pos.xyz - cam.eye.xyz);
    if id % 3u == 0u { out.bary = vec3<f32>(1,0,0); }
    else if id % 3u == 1u { out.bary = vec3<f32>(0,1,0); }
    else { out.bary = vec3<f32>(0,0,1); }
    out.uv = vec2<f32>(0.0); out.kind = v.color.w;
    return out;
}
@fragment fn fs(v: Out) -> @location(0) vec4<f32> {
    let n = normalize(v.normal);
    let sun = normalize(cam.sun.xyz);
    let diffuse = max(0.0, dot(n, sun));
    let sky = 0.38 + 0.22 * max(0.0, n.y);
    let ao = 0.72 + 0.28 * max(0.0, n.y);
    var color = v.color * (sky + diffuse * cam.sun.w) * ao;
    let detail = 0.94 + 0.06 * sin(v.world.x * 12.3 + v.world.z * 9.7 + v.world.y * 4.1);
    color *= detail;
    if cam.misc.z > 0.5 && abs(length(v.world - cam.brush.xyz) - cam.brush_params.x) < 0.45 {
        color = mix(color, vec3<f32>(1.0,0.25,0.75), 0.72);
    }
    if cam.params.w > 0.5 && cam.params.w < 1.5 {
        let cell = abs(fract(v.world.xz / 32.0) - vec2<f32>(0.5));
        if max(cell.x, cell.y) > 0.485 { color = vec3<f32>(0.1, 0.8, 1.0); }
    }
    if cam.params.w > 1.5 && cam.params.w < 2.5 { color = n * 0.5 + vec3<f32>(0.5); }
    if cam.params.w > 2.5 && cam.params.w < 3.5 {
        let palettes = array<vec3<f32>, 5>(vec3<f32>(0.2,0.8,0.2), vec3<f32>(0.0,0.5,0.1),
            vec3<f32>(0.9,0.75,0.3), vec3<f32>(0.5,0.5,0.55), vec3<f32>(0.9,0.95,1.0));
        color = palettes[u32(v.kind + 0.5)];
    }
    if cam.params.w > 3.5 && cam.params.w < 4.5 { color = vec3<f32>(v.world.y / 48.0, 0.4, 1.0 - v.world.y / 48.0); }
    if cam.params.w > 4.5 {
        let edge = min(v.bary.x, min(v.bary.y, v.bary.z));
        if edge < 0.035 { color = vec3<f32>(0.03, 0.05, 0.07); }
    }
    let fog = 1.0 - exp(-v.distance * v.distance * 0.000035);
    let fog_color = vec3<f32>(0.48, 0.65, 0.82);
    return vec4<f32>(mix(color, fog_color, clamp(fog, 0.0, 0.94)), 1.0);
}
@vertex fn vs_water(@builtin(vertex_index) id: u32) -> Out {
    var out: Out;
    if id >= meta[1] { out.pos = vec4<f32>(0.0,0.0,2.0,1.0); return out; }
    let v = vertices[id];
    var p = v.pos.xyz;
    p.y += sin(p.x * 0.55 + cam.params.z * 1.7) * 0.045
    + sin(p.z * 0.72 - cam.params.z * 1.2) * 0.035;
    out.pos = project(p);
    out.world = p; out.normal = vec3<f32>(0,1,0); out.color = v.color.xyz;
    out.distance = length(p - cam.eye.xyz); out.bary = vec3<f32>(0.0);
    out.uv = vec2<f32>(0.0); out.kind = 0.0;
    return out;
}
@fragment fn fs_water(v: Out) -> @location(0) vec4<f32> {
    let ripple = sin(v.world.x * 1.4 + cam.params.z * 2.0) * sin(v.world.z * 1.1 - cam.params.z);
    let view = normalize(cam.eye.xyz - v.world);
    let fresnel = pow(1.0 - max(0.0, view.y), 3.0);
    let sky = vec3<f32>(0.42, 0.65, 0.82);
    var color = mix(v.color, sky, 0.18 + fresnel * 0.55);
    color += vec3<f32>(0.12, 0.16, 0.18) * max(0.0, ripple) * 0.35;
    let fog = 1.0 - exp(-v.distance * v.distance * 0.000035);
    color = mix(color, vec3<f32>(0.48,0.65,0.82), clamp(fog,0.0,0.94));
    return vec4<f32>(color, 0.66);
}
@vertex fn vs_plant(@builtin(vertex_index) id: u32,
    @builtin(instance_index) instance: u32) -> Out {
    var out: Out;
    if instance >= meta[2] { out.pos = vec4<f32>(0.0,0.0,2.0,1.0); return out; }
    let plant = vertices[instance];
    let lod_distance = length(plant.pos.xyz - cam.eye.xyz);
    if (lod_distance > 150.0 && instance % 2u == 1u) || lod_distance > 230.0 {
        out.pos = vec4<f32>(0.0,0.0,2.0,1.0); return out;
    }
    let kind = plant.color.w;
    var corner = id % 6u;
    if corner == 3u { corner = 0u; }
    if corner == 4u { corner = 2u; }
    if corner == 5u { corner = 3u; }
    let ux = f32(corner == 1u || corner == 2u);
    let uy = f32(corner >= 2u);
    var size = vec2<f32>(0.45, 1.0) * plant.pos.w;
    if kind < 1.5 { size = vec2<f32>(2.8, 5.2) * plant.pos.w; }
    if kind > 2.5 { size = vec2<f32>(0.8, 2.6) * plant.pos.w; }
    var p = plant.pos.xyz;
    let side = (ux - 0.5) * size.x;
    if id < 6u { p.x += side; } else { p.z += side; }
    p.y += uy * size.y;
    p.x += sin(cam.params.z * 1.5 + plant.pos.x * 0.3 + plant.pos.z * 0.2) * uy * uy * 0.16;
    out.pos = project(p);
    out.world = p; out.color = plant.color.xyz; out.kind = kind;
    out.normal = normalize(vec3<f32>(0.3,0.8,0.2)); out.distance = length(p - cam.eye.xyz);
    out.bary = vec3<f32>(0.0); out.uv = vec2<f32>(ux, uy);
    return out;
}
@fragment fn fs_plant(v: Out) -> @location(0) vec4<f32> {
    var color = v.color;
    if v.kind < 1.5 {
        let trunk = abs(v.uv.x - 0.5) < 0.065 && v.uv.y < 0.62;
        let canopy_width = (1.0 - v.uv.y) * 0.52 + 0.08;
        let canopy = v.uv.y > 0.28 && abs(v.uv.x - 0.5) < canopy_width;
        if !trunk && !canopy { discard; }
        if trunk { color = vec3<f32>(0.24,0.13,0.065); }
        else { color *= 0.72 + v.uv.y * 0.55; }
    } else if v.kind < 2.5 {
        let blade = abs(v.uv.x - 0.5 + sin(v.uv.y * 4.0) * 0.08) < 0.11 * (1.0 - v.uv.y * 0.6);
        if !blade { discard; }
        color *= 0.8 + v.uv.y * 0.4;
    } else {
        if abs(v.uv.x - 0.5) > 0.16 { discard; }
        color = vec3<f32>(0.20,0.42,0.22);
    }
    let light = 0.55 + 0.45 * max(0.0, dot(normalize(v.normal), normalize(cam.sun.xyz)));
    color *= light;
    let fog = 1.0 - exp(-v.distance * v.distance * 0.000035);
    return vec4<f32>(mix(color, vec3<f32>(0.48,0.65,0.82), clamp(fog,0.0,0.94)), 1.0);
}
