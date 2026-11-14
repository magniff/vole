// The Mandelbulb, ray-marched in one full-screen fragment shader.
//
// A primary ray first meets the fractal's bounding sphere, so the sky is
// one sphere intersection, not a hundred distance evaluations. Inside it,
// sphere tracing uses the analytic distance estimator; the hit epsilon
// grows with the pixel's footprint at the hit's depth, which stops
// over-marching distant pixels. The power is an integer, so r^p and r^(p-1)
// are a few multiplies rather than pow().

struct Params {
    eye: vec4<f32>,       // xyz camera, w time (seconds)
    right: vec4<f32>,     // xyz camera right, w tan(fov / 2)
    up: vec4<f32>,        // xyz camera up, w aspect
    forward: vec4<f32>,   // xyz camera forward, w power
    dims: vec4<f32>,      // width, height, march steps, pixel radius
    quality: vec4<f32>,   // shadow steps, AO steps, palette, exposure
    misc: vec4<f32>,      // far plane, silhouette glow, 0, 0
}

@group(0) @binding(0) var<uniform> u: Params;

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

// Small integer powers, never exp/log. Three or four squarings cover
// every power the UI offers (2 through 16).
fn power_int(x: f32, n: i32) -> f32 {
    var result = 1.0;
    var base = x;
    var e = n;
    while e > 0 {
        if (e & 1) == 1 { result *= base; }
        base *= base;
        e >>= 1;
    }
    return result;
}

// distance, then the orbit trap used for colour.
fn mandelbulb(p: vec3<f32>) -> vec4<f32> {
    var z = p;
    var dr = 1.0;
    var r = 0.0;
    var trap = vec3<f32>(10.0);
    let power = i32(u.forward.w + 0.5);
    for (var i = 0u; i < 16u; i += 1u) {
        r = length(z);
        if r > 2.0 { break; }
        let theta = acos(clamp(z.z / max(r, 0.0000001), -1.0, 1.0));
        let phi = atan2(z.y, z.x);
        dr = power_int(r, power - 1) * f32(power) * dr + 1.0;
        let zr = power_int(r, power);
        let t = theta * f32(power);
        let ph = phi * f32(power);
        let st = sin(t);
        z = zr * vec3<f32>(st * cos(ph), st * sin(ph), cos(t)) + p;
        trap = min(trap, abs(z));
    }
    let radius = max(r, 0.0000001);
    return vec4<f32>(0.5 * log(radius) * radius / max(dr, 0.0000001), trap);
}

// Entry and exit of the sphere around the whole fractal. Empty pixels do
// no distance evaluations at all.
fn bounding_sphere(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    let b = dot(ro, rd);
    let c = dot(ro, ro) - 1.44; // radius 1.2
    let disc = b * b - c;
    if disc < 0.0 { return vec2<f32>(-1.0, -1.0); }
    let s = sqrt(disc);
    return vec2<f32>(-b - s, -b + s);
}

struct Hit {
    t: f32,
    steps: f32,
    closest: f32,
    trap: vec3<f32>,
}

fn march(ro: vec3<f32>, rd: vec3<f32>) -> Hit {
    let span = bounding_sphere(ro, rd);
    var t = max(span.x, 0.0);
    let end = min(span.y, u.misc.x);
    var steps = 0.0;
    var closest = 1000.0;
    var trap = vec3<f32>(0.0);
    if span.y <= max(span.x, 0.0) {
        return Hit(t, steps, closest, trap);
    }
    for (var i = 0u; i < 256u; i += 1u) {
        if f32(i) >= u.dims.z || t > end { break; }
        let de = mandelbulb(ro + rd * t);
        closest = min(closest, abs(de.x));
        let eps = max(0.00008, t * u.dims.w * 0.65);
        if de.x < eps {
            return Hit(t, f32(i + 1u), closest, de.yzw);
        }
        t += de.x * 0.85;
        steps = f32(i + 1u);
    }
    return Hit(-1.0, steps, closest, trap);
}

// Four distance evaluations, not six, for a normal.
fn normal_at(p: vec3<f32>, t: f32) -> vec3<f32> {
    let e = max(0.00004, t * u.dims.w * 0.25);
    let a = vec2<f32>(1.0, -1.0) * e;
    return normalize(
        a.xyy * mandelbulb(p + a.xyy).x +
        a.yyx * mandelbulb(p + a.yyx).x +
        a.yxy * mandelbulb(p + a.yxy).x +
        a.xxx * mandelbulb(p + a.xxx).x
    );
}

fn soft_shadow(ro: vec3<f32>, rd: vec3<f32>) -> f32 {
    let count = u32(u.quality.x + 0.5);
    if count == 0u { return 1.0; }
    var visibility = 1.0;
    var t = 0.012;
    for (var i = 0u; i < 32u; i += 1u) {
        if i >= count { break; }
        let h = mandelbulb(ro + rd * t).x;
        visibility = min(visibility, 12.0 * h / t);
        if visibility < 0.025 || t > 3.0 { break; }
        t += clamp(h, 0.008, 0.16);
    }
    return clamp(visibility, 0.0, 1.0);
}

fn ambient_occlusion(p: vec3<f32>, n: vec3<f32>) -> f32 {
    let count = u32(u.quality.y + 0.5);
    if count == 0u { return 1.0; }
    var occlusion = 0.0;
    var weight = 1.0;
    for (var i = 1u; i <= 4u; i += 1u) {
        if i > count { break; }
        let h = 0.008 + 0.055 * f32(i);
        let d = mandelbulb(p + n * h).x;
        occlusion += (h - d) * weight;
        weight *= 0.65;
    }
    return clamp(1.0 - occlusion * 3.0, 0.0, 1.0);
}

fn sky(rd: vec3<f32>) -> vec3<f32> {
    let t = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
    let low = vec3<f32>(0.010, 0.018, 0.038);
    let high = vec3<f32>(0.10, 0.18, 0.28);
    return mix(low, high, t * t);
}

fn material(trap: vec3<f32>) -> vec3<f32> {
    let v = clamp(trap, vec3<f32>(0.0), vec3<f32>(1.0));
    let palette = i32(u.quality.z + 0.5);
    if palette == 1 {
        return vec3<f32>(0.035 + 0.18 * v.x, 0.16 + 0.72 * v.y, 0.26 + 0.68 * v.z);
    }
    if palette == 2 {
        return vec3<f32>(0.28 + 0.66 * v.x, 0.07 + 0.30 * v.y, 0.36 + 0.58 * v.z);
    }
    if palette == 3 {
        return vec3<f32>(0.56 + 0.36 * v.x, 0.49 + 0.38 * v.y, 0.36 + 0.48 * v.z);
    }
    return vec3<f32>(0.10 + 0.92 * v.z, 0.12 + 0.52 * v.y, 0.20 + 0.26 * v.x);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + vec3<f32>(b))) / (x * (c * x + vec3<f32>(d)) + vec3<f32>(e)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

@fragment fn fs(v: Vertex) -> @location(0) vec4<f32> {
    let uv = vec2<f32>(v.uv.x * 2.0 - 1.0, 1.0 - v.uv.y * 2.0);
    let rd = normalize(u.forward.xyz + u.right.xyz * (uv.x * u.up.w * u.right.w)
        + u.up.xyz * (uv.y * u.right.w));
    let ro = u.eye.xyz;
    let hit = march(ro, rd);
    var color = sky(rd);
    if hit.t > 0.0 {
        let p = ro + rd * hit.t;
        let n = normal_at(p, hit.t);
        let base = material(hit.trap);
        let light = normalize(vec3<f32>(-0.55, 0.78, -0.42));
        let diffuse = max(dot(n, light), 0.0);
        let visibility = soft_shadow(p + n * 0.004, light);
        let ao = ambient_occlusion(p, n);
        let hemisphere = 0.35 + 0.30 * max(n.y, 0.0);
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let specular = pow(max(dot(reflect(-light, n), -rd), 0.0), 28.0);
        color = base * (hemisphere * ao + diffuse * visibility * 1.25)
            + vec3<f32>(0.20, 0.28, 0.38) * ao * 0.30
            + base * rim * 0.45
            + vec3<f32>(1.0, 0.88, 0.70) * specular * visibility * 0.42;
        color = mix(color, sky(rd), 1.0 - exp(-hit.t * 0.025));
    } else {
        // A near silhouette leaves a bloom around the bulb, including
        // rays that exhausted the step budget rather than escaping.
        let aura = exp(-hit.closest * 38.0) * u.misc.y;
        color += material(vec3<f32>(0.35, 0.22, 0.12)) * aura;
    }
    color = aces(color * u.quality.w);
    color = pow(color, vec3<f32>(1.0 / 2.2));
    return vec4<f32>(color, 1.0);
}
