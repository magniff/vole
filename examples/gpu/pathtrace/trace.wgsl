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
}
struct Hit {
    t: f32,
    p: vec3<f32>,
    n: vec3<f32>,
    id: u32,
}
struct Surface {
    normal: vec4<f32>,
    albedo: vec4<f32>,
    info: vec4<f32>,
}
struct LightSample {
    wi: vec3<f32>,
    distance: f32,
    pdf: f32,
}
@group(0) @binding(0) var<uniform> u: Params;
@group(0) @binding(1) var<storage, read_write> accum: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read_write> gbuffer: array<Surface>;
@group(0) @binding(3) var<storage, read_write> rays: array<vec4<f32>>;
var<private> rng_state: u32;
var<private> intersection_tests: u32;
var<private> recording: bool;
var<private> path_nodes: u32;
fn rand() -> f32 {
    rng_state = rng_state * 747796405u + 2891336453u;
    var word = ((rng_state >> ((rng_state >> 28u) + 4u)) ^ rng_state) * 277803737u;
    word = (word >> 22u) ^ word;
    return f32(word) * 2.3283064365386963e-10;
}
fn unit_vector() -> vec3<f32> {
    let z = rand() * 2.0 - 1.0;
    let a = rand() * 6.28318530718;
    let r = sqrt(max(0.0, 1.0 - z * z));
    return vec3<f32>(r * cos(a), r * sin(a), z);
}
fn basis(n: vec3<f32>) -> mat3x3<f32> {
    var tangent = vec3<f32>(1.0, 0.0, 0.0);
    if abs(n.z) < 0.999 { tangent = vec3<f32>(0.0, 1.0, 0.0); }
    let x = normalize(cross(tangent, n));
    let y = cross(n, x);
    return mat3x3<f32>(x, y, n);
}
fn matte(albedo: vec3<f32>, roughness: f32, metallic: f32) -> Material {
    return Material(vec4<f32>(albedo, roughness),
        vec4<f32>(metallic, 1.45, 0.0, 0.0), vec4<f32>(1.0, 1.0, 1.0, 0.0));
}
fn light_material() -> Material {
    return Material(vec4<f32>(0.0), vec4<f32>(0.0),
        vec4<f32>(u.light_color.xyz * u.light_pos.w, 0.0));
}
fn miss() -> Hit {
    return Hit(1.0e20, vec3<f32>(0.0), vec3<f32>(0.0, 1.0, 0.0), 0u);
}
fn record_point(p: vec3<f32>, event: f32) {
    if recording && path_nodes < 15u {
        rays[path_nodes] = vec4<f32>(p, event);
        path_nodes += 1u;
    }
}
fn sphere(ro: vec3<f32>, rd: vec3<f32>, center: vec3<f32>, radius: f32,
    id: u32, best: Hit) -> Hit {
    intersection_tests += 1u;
    var h = best;
    let oc = ro - center;
    let b = dot(oc, rd);
    let c = dot(oc, oc) - radius * radius;
    let discriminant = b * b - c;
    if discriminant > 0.0 {
        let root = sqrt(discriminant);
        var t = -b - root;
        if t <= 0.0001 { t = -b + root; }
        if t > 0.0001 && t < h.t {
            let p = ro + rd * t;
            h = Hit(t, p, (p - center) / radius, id);
        }
    }
    return h;
}
fn plane(ro: vec3<f32>, rd: vec3<f32>, normal: vec3<f32>, d: f32,
    id: u32, best: Hit) -> Hit {
    intersection_tests += 1u;
    var h = best;
    let denominator = dot(rd, normal);
    if abs(denominator) > 0.000001 {
        let t = (d - dot(ro, normal)) / denominator;
        if t > 0.0001 && t < h.t {
            h = Hit(t, ro + rd * t, normal, id);
        }
    }
    return h;
}
fn area_light(ro: vec3<f32>, rd: vec3<f32>, best: Hit) -> Hit {
    intersection_tests += 1u;
    var h = best;
    if abs(rd.y) > 0.000001 {
        let t = (5.0 - ro.y) / rd.y;
        let p = ro + rd * t;
        if t > 0.0001 && t < h.t && abs(p.x - u.light_pos.x) <= u.light_size.x * 0.5
        && abs(p.z - u.light_pos.z) <= u.light_size.y * 0.5 {
            h = Hit(t, p, vec3<f32>(0.0, -1.0, 0.0), 9u);
        }
    }
    return h;
}
fn shadow_sphere(ro: vec3<f32>, rd: vec3<f32>, center: vec3<f32>, radius: f32,
    max_t: f32) -> bool {
    intersection_tests += 1u;
    let oc = ro - center;
    let b = dot(oc, rd);
    let c = dot(oc, oc) - radius * radius;
    let discriminant = b * b - c;
    if discriminant <= 0.0 { return false; }
    let root = sqrt(discriminant);
    let near = -b - root;
    if near > 0.0001 && near < max_t { return true; }
    let far = -b + root;
    return far > 0.0001 && far < max_t;
}
fn shadow_plane(ro: vec3<f32>, rd: vec3<f32>, normal: vec3<f32>, d: f32,
    max_t: f32) -> bool {
    intersection_tests += 1u;
    let denominator = dot(rd, normal);
    if abs(denominator) <= 0.000001 { return false; }
    let t = (d - dot(ro, normal)) / denominator;
    return t > 0.0001 && t < max_t;
}
fn visible(ro: vec3<f32>, rd: vec3<f32>, distance: f32) -> bool {
    let max_t = distance - 0.001;
    if u.flags.y > 0.5 {
        if shadow_plane(ro, rd, vec3<f32>(0.0, 1.0, 0.0), -2.2, max_t) { return false; }
        if shadow_plane(ro, rd, vec3<f32>(0.0, 0.0, 1.0), -1.2, max_t) { return false; }
        for (var row: u32 = 0u; row < 4u; row += 1u) {
            for (var column: u32 = 0u; column < 4u; column += 1u) {
                let center = vec3<f32>((f32(column) - 1.5) * 1.20, (1.5 - f32(row)) * 1.05, 0.0);
                if shadow_sphere(ro, rd, center, 0.45, max_t) { return false; }
            }
        }
        return true;
    }
    if shadow_plane(ro, rd, vec3<f32>(0.0, 1.0, 0.0), -1.0, max_t) { return false; }
    if shadow_plane(ro, rd, vec3<f32>(1.0, 0.0, 0.0), -4.2, max_t) { return false; }
    if shadow_plane(ro, rd, vec3<f32>(-1.0, 0.0, 0.0), -4.2, max_t) { return false; }
    if shadow_plane(ro, rd, vec3<f32>(0.0, 0.0, 1.0), -3.2, max_t) { return false; }
    if shadow_sphere(ro, rd, vec3<f32>(-2.0, 0.0, 0.0), 1.0, max_t) { return false; }
    if shadow_sphere(ro, rd, vec3<f32>(0.0, 0.0, -0.35), 1.0, max_t) { return false; }
    if shadow_sphere(ro, rd, vec3<f32>(2.0, 0.0, 0.0), 1.0, max_t) { return false; }
    if shadow_sphere(ro, rd, vec3<f32>(0.0, -0.45, 2.1), 0.55, max_t) { return false; }
    return true;
}
fn grid_material(column: u32, row: u32) -> Material {
    let roughness = 0.035 + f32(row) * 0.30;
    let metallic = f32(column) / 3.0;
    let tint = mix(vec3<f32>(0.56, 0.60, 0.66), vec3<f32>(0.83, 0.55, 0.20), metallic);
    return matte(tint, roughness, metallic);
}
fn hit_material(h: Hit) -> Material {
    if h.id < 4u { return u.materials[h.id]; }
    if h.id == 4u {
        var mat = matte(vec3<f32>(0.42, 0.45, 0.50), 0.12, 0.72);
        let cell = floor(h.p.x * 0.65) + floor(h.p.z * 0.65);
        let parity = cell - 2.0 * floor(cell * 0.5);
        let color = mix(vec3<f32>(0.12, 0.14, 0.17), vec3<f32>(0.58, 0.61, 0.65), parity);
        mat.albedo = vec4<f32>(color, mat.albedo.w);
        return mat;
    }
    if h.id == 5u { return matte(vec3<f32>(0.62, 0.055, 0.035), 0.72, 0.0); }
    if h.id == 6u { return matte(vec3<f32>(0.035, 0.16, 0.62), 0.72, 0.0); }
    if h.id == 7u { return matte(vec3<f32>(0.56, 0.54, 0.49), 0.78, 0.0); }
    if h.id == 9u { return light_material(); }
    if h.id == 20u { return matte(vec3<f32>(0.34, 0.37, 0.42), 0.18, 0.65); }
    if h.id == 21u { return matte(vec3<f32>(0.42, 0.44, 0.48), 0.65, 0.0); }
    if h.id >= 30u {
        let cell = h.id - 30u;
        return grid_material(cell % 4u, cell / 4u);
    }
    return matte(vec3<f32>(0.0), 1.0, 0.0);
}
fn scene(ro: vec3<f32>, rd: vec3<f32>) -> Hit {
    var h = miss();
    if u.flags.y > 0.5 {
        h = plane(ro, rd, vec3<f32>(0.0, 1.0, 0.0), -2.2, 20u, h);
        h = plane(ro, rd, vec3<f32>(0.0, 0.0, 1.0), -1.2, 21u, h);
        for (var row: u32 = 0u; row < 4u; row += 1u) {
            for (var column: u32 = 0u; column < 4u; column += 1u) {
                let center = vec3<f32>((f32(column) - 1.5) * 1.20, (1.5 - f32(row)) * 1.05, 0.0);
                h = sphere(ro, rd, center, 0.45, 30u + row * 4u + column, h);
            }
        }
        return area_light(ro, rd, h);
    }
    h = plane(ro, rd, vec3<f32>(0.0, 1.0, 0.0), -1.0, 4u, h);
    h = plane(ro, rd, vec3<f32>(1.0, 0.0, 0.0), -4.2, 5u, h);
    h = plane(ro, rd, vec3<f32>(-1.0, 0.0, 0.0), -4.2, 6u, h);
    h = plane(ro, rd, vec3<f32>(0.0, 0.0, 1.0), -3.2, 7u, h);
    h = sphere(ro, rd, vec3<f32>(-2.0, 0.0, 0.0), 1.0, 0u, h);
    h = sphere(ro, rd, vec3<f32>(0.0, 0.0, -0.35), 1.0, 1u, h);
    h = sphere(ro, rd, vec3<f32>(2.0, 0.0, 0.0), 1.0, 2u, h);
    h = sphere(ro, rd, vec3<f32>(0.0, -0.45, 2.1), 0.55, 3u, h);
    return area_light(ro, rd, h);
}
fn sky(rd: vec3<f32>) -> vec3<f32> {
    let t = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
    let gradient = mix(vec3<f32>(0.10, 0.13, 0.19), vec3<f32>(0.34, 0.46, 0.68), t);
    let lobe = max(0.0, dot(rd, normalize(vec3<f32>(-0.5, 0.65, 0.35))));
    let lobe2 = lobe * lobe;
    let lobe4 = lobe2 * lobe2;
    let lobe8 = lobe4 * lobe4;
    let studio = lobe8 * lobe8 * lobe2;
    return (gradient + vec3<f32>(1.0, 0.82, 0.62) * studio * 2.2) * u.env.x;
}
fn sample_light(p: vec3<f32>) -> LightSample {
    let q = u.light_pos.xyz + vec3<f32>((rand() - 0.5) * u.light_size.x, 0.0,
        (rand() - 0.5) * u.light_size.y);
    let delta = q - p;
    let distance2 = dot(delta, delta);
    let distance = sqrt(distance2);
    let wi = delta / distance;
    let cosine = max(0.0001, dot(vec3<f32>(0.0, -1.0, 0.0), -wi));
    let pdf = distance2 / (u.light_size.x * u.light_size.y * cosine);
    return LightSample(wi, distance, pdf);
}
fn transmittance(distance: f32) -> vec3<f32> {
    return exp(vec3<f32>(-u.env.y * distance));
}
fn fresnel(f0: vec3<f32>, cosine: f32) -> vec3<f32> {
    let one = 1.0 - cosine;
    let squared = one * one;
    return f0 + (vec3<f32>(1.0) - f0) * (squared * squared * one);
}
fn ggx_d(noh: f32, roughness: f32) -> f32 {
    let alpha = max(0.0001, roughness * roughness);
    let alpha2 = alpha * alpha;
    let d = noh * noh * (alpha2 - 1.0) + 1.0;
    return alpha2 / max(0.000001, 3.14159265359 * d * d);
}
fn eval_bsdf(n: vec3<f32>, wo: vec3<f32>, wi: vec3<f32>, mat: Material) -> vec3<f32> {
    let nol = max(0.0, dot(n, wi));
    let nov = max(0.0001, dot(n, wo));
    let half = normalize(wo + wi);
    let noh = max(0.0, dot(n, half));
    let voh = max(0.0001, dot(wo, half));
    let f0 = mix(vec3<f32>(0.04), mat.albedo.xyz, mat.params.x);
    let f = fresnel(f0, voh);
    let d = ggx_d(noh, mat.albedo.w);
    let k = (mat.albedo.w + 1.0) * (mat.albedo.w + 1.0) * 0.125;
    let gv = nov * (1.0 - k) + k;
    let gl = nol * (1.0 - k) + k;
    let specular = d * f / (4.0 * gv * gl);
    let diffuse = (vec3<f32>(1.0) - f) * (1.0 - mat.params.x) * mat.albedo.xyz / 3.14159265359;
    return specular + diffuse;
}
fn direct_surface(p: vec3<f32>, n: vec3<f32>, wo: vec3<f32>, mat: Material) -> vec3<f32> {
    let light = sample_light(p);
    let nol = max(0.0, dot(n, light.wi));
    if nol == 0.0 { return vec3<f32>(0.0); }
    if !visible(p + n * 0.001, light.wi, light.distance) { return vec3<f32>(0.0); }
    let brdf = eval_bsdf(n, wo, light.wi, mat);
    return brdf * u.light_color.xyz * (u.light_pos.w * nol / light.pdf) * transmittance(light.distance);
}
fn phase(cosine: f32) -> f32 {
    let g = u.env.z;
    let denominator = max(0.001, 1.0 + g * g - 2.0 * g * cosine);
    return (1.0 - g * g) / (12.56637061436 * denominator * sqrt(denominator));
}
fn sample_phase(direction: vec3<f32>) -> vec3<f32> {
    let g = u.env.z;
    var cosine = 1.0 - 2.0 * rand();
    if abs(g) > 0.001 {
        let ratio = (1.0 - g * g) / (1.0 - g + 2.0 * g * rand());
        cosine = (1.0 + g * g - ratio * ratio) / (2.0 * g);
    }
    let phi = rand() * 6.28318530718;
    let sine = sqrt(max(0.0, 1.0 - cosine * cosine));
    return normalize(basis(direction) * vec3<f32>(sine * cos(phi), sine * sin(phi), cosine));
}
fn direct_medium(p: vec3<f32>, direction: vec3<f32>) -> vec3<f32> {
    let light = sample_light(p);
    if !visible(p, light.wi, light.distance) { return vec3<f32>(0.0); }
    return u.light_color.xyz * (u.light_pos.w * phase(dot(direction, light.wi)) / light.pdf)
    * transmittance(light.distance);
}
fn sample_ggx(n: vec3<f32>, roughness: f32) -> vec3<f32> {
    let alpha = max(0.0001, roughness * roughness);
    let phi = rand() * 6.28318530718;
    let r = rand();
    let cosine = sqrt((1.0 - r) / (1.0 + (alpha * alpha - 1.0) * r));
    let sine = sqrt(max(0.0, 1.0 - cosine * cosine));
    return normalize(basis(n) * vec3<f32>(sine * cos(phi), sine * sin(phi), cosine));
}
fn trace(ro: vec3<f32>, rd: vec3<f32>, index: u32, sample: u32) -> vec3<f32> {
    var origin = ro;
    var direction = rd;
    var radiance = vec3<f32>(0.0);
    var throughput = vec3<f32>(1.0);
    var specular = false;
    var depth_traced = 0u;
    intersection_tests = 0u;
    if recording {
        path_nodes = 1u;
        rays[0] = vec4<f32>(ro, 0.0);
    }
    for (var bounce: u32 = 0u; bounce < 6u; bounce += 1u) {
        depth_traced = bounce + 1u;
        let h = scene(origin, direction);
        var medium = false;
        var travel = h.t;
        if u.env.y > 0.00001 {
            let free_flight = -log(max(0.000001, 1.0 - rand())) / u.env.y;
            if free_flight < h.t { medium = true; travel = free_flight; }
        }
        if medium {
            let p = origin + direction * travel;
            radiance += throughput * direct_medium(p, direction);
            if u.flags.z < 0.5 { break; }
            direction = sample_phase(direction);
            throughput *= vec3<f32>(0.94, 0.96, 0.99);
            origin = p + direction * 0.001;
            specular = false;
            record_point(p, 4.0);
        } else {
            if h.t > 1.0e19 {
                radiance += throughput * sky(direction);
                record_point(origin + direction * 20.0, 0.0);
                break;
            }
            let mat = hit_material(h);
            let front = dot(direction, h.n) < 0.0;
            var n = h.n;
            if !front { n = -n; }
            if sample == 0u && bounce == 0u {
                gbuffer[index].normal = vec4<f32>(n, h.t);
                gbuffer[index].albedo = vec4<f32>(mat.albedo.xyz, f32(h.id));
            }
            if h.id == 9u {
                if bounce == 0u || specular { radiance += throughput * mat.absorption.xyz; }
                record_point(h.p, 2.0);
                break;
            }
            if mat.absorption.w > 0.0 {
                radiance += throughput * mat.absorption.xyz * mat.absorption.w;
                record_point(h.p, 1.0);
                break;
            }
            if mat.params.z > 0.5 {
                if !front {
                    let extinction = (vec3<f32>(1.0) - mat.absorption.xyz) * mat.params.w;
                    throughput *= exp(-extinction * h.t);
                }
                var eta = mat.params.y;
                if front { eta = 1.0 / eta; }
                let cosine = min(1.0, max(0.0, dot(-direction, n)));
                var r0 = (1.0 - mat.params.y) / (1.0 + mat.params.y);
                r0 = r0 * r0;
                let one = 1.0 - cosine;
                let squared = one * one;
                let reflectance = r0 + (1.0 - r0) * squared * squared * one;
                let k = 1.0 - eta * eta * (1.0 - cosine * cosine);
                var refracted = vec3<f32>(0.0);
                if k >= 0.0 { refracted = eta * direction + (eta * cosine - sqrt(k)) * n; }
                if dot(refracted, refracted) == 0.0 || rand() < reflectance {
                    direction = reflect(direction, n);
                    record_point(h.p, 2.0);
                } else {
                    direction = refracted;
                    record_point(h.p, 3.0);
                }
                direction = normalize(direction);
                throughput *= mat.albedo.xyz;
                specular = true;
            } else {
                let wo = normalize(-direction);
                radiance += throughput * direct_surface(h.p, n, wo, mat);
                if u.flags.z < 0.5 {
                    record_point(h.p, 1.0);
                    break;
                }
                let specular_probability = 0.25 + 0.75 * mat.params.x;
                var next = normalize(n + unit_vector());
                if rand() < specular_probability {
                    let micro_normal = sample_ggx(n, mat.albedo.w);
                    next = reflect(direction, micro_normal);
                }
                let nol = max(0.0, dot(n, next));
                if nol <= 0.0 { break; }
                next = normalize(next);
                let half = normalize(wo + next);
                let noh = max(0.0, dot(n, half));
                let voh = max(0.0001, dot(wo, half));
                let specular_pdf = ggx_d(noh, mat.albedo.w) * noh / (4.0 * voh);
                let diffuse_pdf = nol / 3.14159265359;
                let pdf = specular_probability * specular_pdf + (1.0 - specular_probability) * diffuse_pdf;
                throughput *= eval_bsdf(n, wo, next, mat) * (nol / max(0.0001, pdf));
                direction = next;
                specular = false;
                record_point(h.p, 1.0);
            }
            origin = h.p + direction * 0.001;
        }
        if bounce >= 2u {
            let survival = clamp(max(throughput.x, max(throughput.y, throughput.z)), 0.05, 0.95);
            if rand() > survival { break; }
            throughput /= survival;
        }
    }
    if sample == 0u {
        gbuffer[index].info = vec4<f32>(f32(intersection_tests), f32(depth_traced), 0.0, 0.0);
    }
    if recording { rays[17] = vec4<f32>(f32(path_nodes), 0.0, 0.0, 0.0); }
    return max(radiance, vec3<f32>(0.0));
}
@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let width = u32(u.dims.x);
    let height = u32(u.dims.y);
    if gid.x >= width || gid.y >= height { return; }
    let sample = u32(u.dims.z);
    rng_state = (gid.x * 1973u + gid.y * 9277u + sample * 26699u) ^ 0x9E3779B9u;
    let aspect = u.dims.x / u.dims.y;
    let forward = normalize(u.target.xyz - u.eye.xyz);
    let right = normalize(cross(forward, vec3<f32>(0.0, 1.0, 0.0)));
    let up = cross(right, forward);
    let px = (f32(gid.x) + rand()) / u.dims.x;
    let py = (f32(gid.y) + rand()) / u.dims.y;
    let sx = (px * 2.0 - 1.0) * aspect * u.config.x;
    let sy = (1.0 - py * 2.0) * u.config.x;
    var origin = u.eye.xyz;
    var direction = normalize(forward + right * sx + up * sy);
    if u.config.y > 0.0 {
        let focal = origin + direction * (u.config.z / max(0.001, dot(direction, forward)));
        let angle = rand() * 6.28318530718;
        let radius = sqrt(rand()) * u.config.y;
        origin += right * (cos(angle) * radius) + up * (sin(angle) * radius);
        direction = normalize(focal - origin);
    }
    let index = gid.y * width + gid.x;
    let selected_x = u32(u.light_size.z * u.dims.x);
    let selected_y = u32(u.light_size.w * u.dims.y);
    recording = u.flags.x == 8.0 && gid.x == selected_x && gid.y == selected_y;
    let color = trace(origin, direction, index, sample);
    var sum = vec3<f32>(0.0);
    var moments = vec3<f32>(0.0);
    if sample > 0u {
        sum = accum[index * 3u].xyz;
        moments = accum[index * 3u + 1u].xyz;
    }
    let luminance = dot(color, vec3<f32>(0.3333333333));
    accum[index * 3u] = vec4<f32>(sum + color, 1.0);
    accum[index * 3u + 1u] = vec4<f32>(moments + vec3<f32>(luminance * luminance), 1.0);
    if sample == 0u { accum[index * 3u + 2u] = vec4<f32>(color, 1.0); }
}
