// The observer's frame: one ray per film pixel is aberrated into the village,
// the geometry is Lorentz-contracted along the motion, and the radiance that
// comes back is beamed and Doppler-shifted. The village is a static list of
// rotated boxes and spheres; there is no BVH because it is thirty metres
// across.
//
// This is not a full spectral renderer. The Doppler shift keeps the physical
// frequency factor D = gamma * (1 + beta . d) and the beaming intensity
// D^3, and approximates the colour change with a blackbody gain plus a hue
// bias toward violet ahead and ember red behind. The comparison between the
// regimes (1.1x, 2x, 1000x) is the point, not the exact chroma of a leaf at
// beta = 0.9.

struct Params {
    eye: vec4<f32>,      // xyz eye, w seconds
    forward: vec4<f32>,  // xyz, w tan(fov / 2)
    right: vec4<f32>,    // xyz, w aspect
    up: vec4<f32>,       // xyz, w exposure
    beta: vec4<f32>,     // xyz v/c, w |v|/c
    gamma: vec4<f32>,    // x gamma, y multiplier, z walk speed
    effects: vec4<f32>,  // doppler, aberration, beaming, contraction
    sun: vec4<f32>,      // xyz toward the sun, w intensity
    misc: vec4<f32>,     // x orb mask, y width, z height, w unused
};
@group(0) @binding(0) var<uniform> u: Params;
@group(0) @binding(1) var<storage, read_write> film: array<vec4<f32>>;

struct Box {
    c: vec4<f32>,   // xyz centre, w cos(angle)
    h: vec4<f32>,   // xyz half extent, w sin(angle)
    col: vec4<f32>, // rgb albedo, w emissive
};
struct Ball {
    c: vec4<f32>,   // xyz centre, w radius
    col: vec4<f32>, // rgb albedo, w emissive
};
struct Scene {
    boxes: array<Box, 58>,
    balls: array<Ball, 30>,
    orbs: array<Ball, 8>,
};
@group(0) @binding(2) var<storage, read_write> scene: Scene;

const BOX_COUNT: u32 = 58u;
const BOXES_SRC: array<Box, 58> = array<Box, 58>(
    Box(vec4<f32>(0, 1.4, -12, 0.998), vec4<f32>(1.8, 1.4, 1.5, 0.06), vec4<f32>(0.8, 0.72, 0.56, 0)),
    Box(vec4<f32>(0, 3, -12, 0.998), vec4<f32>(2.1, 0.2, 1.8, 0.06), vec4<f32>(0.4, 0.13, 0.1, 0)),
    Box(vec4<f32>(1.118, 3.65, -12.594, 0.998), vec4<f32>(0.16, 0.55, 0.16, 0.06), vec4<f32>(0.4, 0.13, 0.1, 0)),
    Box(vec4<f32>(-0.092, 0.84, -10.463, 0.998), vec4<f32>(0.38, 0.84, 0.05, 0.06), vec4<f32>(0.22, 0.14, 0.09, 0)),
    Box(vec4<f32>(-1.099, 1.792, -10.513, 0.998), vec4<f32>(0.3, 0.24, 0.05, 0.06), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(0.913, 1.792, -10.392, 0.998), vec4<f32>(0.3, 0.24, 0.05, 0.06), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(-9.5, 1.25, -7, 0.853), vec4<f32>(1.6, 1.25, 1.4, 0.523), vec4<f32>(0.72, 0.52, 0.3, 0)),
    Box(vec4<f32>(-9.5, 2.7, -7, 0.853), vec4<f32>(1.9, 0.2, 1.7, 0.523), vec4<f32>(0.26, 0.28, 0.3, 0)),
    Box(vec4<f32>(-8.36, 3.35, -7.023, 0.853), vec4<f32>(0.16, 0.55, 0.16, 0.523), vec4<f32>(0.26, 0.28, 0.3, 0)),
    Box(vec4<f32>(-10.253, 0.75, -5.772, 0.853), vec4<f32>(0.38, 0.75, 0.05, 0.523), vec4<f32>(0.22, 0.14, 0.09, 0)),
    Box(vec4<f32>(-11.022, 1.6, -6.232, 0.853), vec4<f32>(0.3, 0.24, 0.05, 0.523), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(-9.494, 1.6, -5.296, 0.853), vec4<f32>(0.3, 0.24, 0.05, 0.523), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(9, 1.3, -8.5, 0.913), vec4<f32>(1.7, 1.3, 1.5, -0.408), vec4<f32>(0.84, 0.82, 0.76, 0)),
    Box(vec4<f32>(9, 2.8, -8.5, 0.913), vec4<f32>(2, 0.2, 1.8, -0.408), vec4<f32>(0.34, 0.2, 0.12, 0)),
    Box(vec4<f32>(9.662, 3.45, -9.519, 0.913), vec4<f32>(0.16, 0.55, 0.16, -0.408), vec4<f32>(0.34, 0.2, 0.12, 0)),
    Box(vec4<f32>(9.628, 0.78, -7.094, 0.913), vec4<f32>(0.38, 0.78, 0.05, -0.408), vec4<f32>(0.22, 0.14, 0.09, 0)),
    Box(vec4<f32>(8.763, 1.664, -6.697, 0.913), vec4<f32>(0.3, 0.24, 0.05, -0.408), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(10.501, 1.664, -7.473, 0.913), vec4<f32>(0.3, 0.24, 0.05, -0.408), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(-13, 1.15, 6, 0.582), vec4<f32>(1.5, 1.15, 1.3, 0.813), vec4<f32>(0.66, 0.72, 0.66, 0)),
    Box(vec4<f32>(-13, 2.5, 6, 0.582), vec4<f32>(1.8, 0.2, 1.6, 0.813), vec4<f32>(0.4, 0.13, 0.1, 0)),
    Box(vec4<f32>(-12.011, 3.15, 6.399, 0.582), vec4<f32>(0.16, 0.55, 0.16, 0.813), vec4<f32>(0.4, 0.13, 0.1, 0)),
    Box(vec4<f32>(-14.09, 0.69, 6.779, 0.582), vec4<f32>(0.38, 0.69, 0.05, 0.813), vec4<f32>(0.22, 0.14, 0.09, 0)),
    Box(vec4<f32>(-14.587, 1.472, 6.102, 0.582), vec4<f32>(0.3, 0.24, 0.05, 0.813), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(-13.609, 1.472, 7.469, 0.582), vec4<f32>(0.3, 0.24, 0.05, 0.813), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(12.5, 1.25, 5.5, 0.752), vec4<f32>(1.6, 1.25, 1.4, -0.659), vec4<f32>(0.8, 0.72, 0.56, 0)),
    Box(vec4<f32>(12.5, 2.7, 5.5, 0.752), vec4<f32>(1.9, 0.2, 1.7, -0.659), vec4<f32>(0.26, 0.28, 0.3, 0)),
    Box(vec4<f32>(12.816, 3.35, 4.404, 0.752), vec4<f32>(0.16, 0.55, 0.16, -0.659), vec4<f32>(0.26, 0.28, 0.3, 0)),
    Box(vec4<f32>(13.45, 0.75, 6.583, 0.752), vec4<f32>(0.38, 0.75, 0.05, -0.659), vec4<f32>(0.22, 0.14, 0.09, 0)),
    Box(vec4<f32>(12.782, 1.6, 7.181, 0.752), vec4<f32>(0.3, 0.24, 0.05, -0.659), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(14.13, 1.6, 5.999, 0.752), vec4<f32>(0.3, 0.24, 0.05, -0.659), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(-6.5, 1.3, 18, 0.976), vec4<f32>(1.7, 1.3, 1.5, 0.218), vec4<f32>(0.72, 0.52, 0.3, 0)),
    Box(vec4<f32>(-6.5, 2.8, 18, 0.976), vec4<f32>(2, 0.2, 1.8, 0.218), vec4<f32>(0.4, 0.13, 0.1, 0)),
    Box(vec4<f32>(-5.361, 3.45, 17.579, 0.976), vec4<f32>(0.16, 0.55, 0.16, 0.218), vec4<f32>(0.4, 0.13, 0.1, 0)),
    Box(vec4<f32>(-6.836, 0.78, 19.503, 0.976), vec4<f32>(0.38, 0.78, 0.05, 0.218), vec4<f32>(0.22, 0.14, 0.09, 0)),
    Box(vec4<f32>(-7.767, 1.664, 19.305, 0.976), vec4<f32>(0.3, 0.24, 0.05, 0.218), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(-5.909, 1.664, 19.72, 0.976), vec4<f32>(0.3, 0.24, 0.05, 0.218), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(8.5, 1.15, 17.5, 0.955), vec4<f32>(1.5, 1.15, 1.3, -0.296), vec4<f32>(0.84, 0.82, 0.76, 0)),
    Box(vec4<f32>(8.5, 2.5, 17.5, 0.955), vec4<f32>(1.8, 0.2, 1.6, -0.296), vec4<f32>(0.34, 0.2, 0.12, 0)),
    Box(vec4<f32>(9.191, 3.15, 16.688, 0.955), vec4<f32>(0.16, 0.55, 0.16, -0.296), vec4<f32>(0.34, 0.2, 0.12, 0)),
    Box(vec4<f32>(8.896, 0.69, 18.78, 0.955), vec4<f32>(0.38, 0.69, 0.05, -0.296), vec4<f32>(0.22, 0.14, 0.09, 0)),
    Box(vec4<f32>(8.096, 1.472, 19.038, 0.955), vec4<f32>(0.3, 0.24, 0.05, -0.296), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(9.701, 1.472, 18.541, 0.955), vec4<f32>(0.3, 0.24, 0.05, -0.296), vec4<f32>(1, 0.74, 0.4, 0.85)),
    Box(vec4<f32>(-4.5, 1.44, 8.5, 1), vec4<f32>(0.24, 1.44, 0.24, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(5.5, 1.17, 8, 1), vec4<f32>(0.195, 1.17, 0.195, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(-10.5, 1.53, 12.5, 1), vec4<f32>(0.255, 1.53, 0.255, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(16, 1.26, 12, 1), vec4<f32>(0.21, 1.26, 0.21, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(16.5, 1.35, -2, 1), vec4<f32>(0.225, 1.35, 0.225, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(-16.5, 1.26, -2.5, 1), vec4<f32>(0.21, 1.26, 0.21, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(2, 1.35, -18.5, 1), vec4<f32>(0.225, 1.35, 0.225, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(-3, 1.44, 23.5, 1), vec4<f32>(0.24, 1.44, 0.24, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(-18, 1.26, 17, 1), vec4<f32>(0.21, 1.26, 0.21, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(18.5, 1.35, 18.5, 1), vec4<f32>(0.225, 1.35, 0.225, 0), vec4<f32>(0.26, 0.17, 0.1, 0)),
    Box(vec4<f32>(3.2, 0.55, 8.2, 0.9), vec4<f32>(0.9, 0.55, 0.55, -0.435), vec4<f32>(0.45, 0.33, 0.19, 0)),
    Box(vec4<f32>(3.2, 1.45, 8.2, 0.9), vec4<f32>(1.15, 0.1, 0.75, -0.435), vec4<f32>(0.55, 0.18, 0.16, 0)),
    Box(vec4<f32>(-4, 0.55, 10.5, 0.939), vec4<f32>(0.9, 0.55, 0.55, 0.343), vec4<f32>(0.45, 0.33, 0.19, 0)),
    Box(vec4<f32>(-4, 1.45, 10.5, 0.939), vec4<f32>(1.15, 0.1, 0.75, 0.343), vec4<f32>(0.16, 0.3, 0.48, 0)),
    Box(vec4<f32>(1, 0.55, 6.2, 0.995), vec4<f32>(0.9, 0.55, 0.55, 0.1), vec4<f32>(0.45, 0.33, 0.19, 0)),
    Box(vec4<f32>(1, 1.45, 6.2, 0.995), vec4<f32>(1.15, 0.1, 0.75, 0.1), vec4<f32>(0.52, 0.4, 0.14, 0)),
);

const BALL_COUNT: u32 = 30u;
const BALLS_SRC: array<Ball, 30> = array<Ball, 30>(
    Ball(vec4<f32>(-4.5, 4.08, 8.5, 1.68), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(-5.38, 3.44, 9.06, 1.248), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(-3.7, 3.28, 7.86, 1.152), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(5.5, 3.315, 8, 1.365), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(4.785, 2.795, 8.455, 1.014), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(6.15, 2.665, 7.48, 0.936), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(-10.5, 4.335, 12.5, 1.785), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(-11.435, 3.655, 13.095, 1.326), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(-9.65, 3.485, 11.82, 1.224), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(16, 3.57, 12, 1.47), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(15.23, 3.01, 12.49, 1.092), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(16.7, 2.87, 11.44, 1.008), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(16.5, 3.825, -2, 1.575), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(15.675, 3.225, -1.475, 1.17), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(17.25, 3.075, -2.6, 1.08), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(-16.5, 3.57, -2.5, 1.47), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(-17.27, 3.01, -2.01, 1.092), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(-15.8, 2.87, -3.06, 1.008), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(2, 3.825, -18.5, 1.575), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(1.175, 3.225, -17.975, 1.17), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(2.75, 3.075, -19.1, 1.08), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(-3, 4.08, 23.5, 1.68), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(-3.88, 3.44, 24.06, 1.248), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(-2.2, 3.28, 22.86, 1.152), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(-18, 3.57, 17, 1.47), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(-18.77, 3.01, 17.49, 1.092), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(-17.3, 2.87, 16.44, 1.008), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(18.5, 3.825, 18.5, 1.575), vec4<f32>(0.16, 0.33, 0.12, 0)),
    Ball(vec4<f32>(17.675, 3.225, 19.025, 1.17), vec4<f32>(0.21, 0.39, 0.15, 0)),
    Ball(vec4<f32>(19.25, 3.075, 17.9, 1.08), vec4<f32>(0.16, 0.33, 0.12, 0)),
);

const ORB_COUNT: u32 = 8u;
const ORBS_SRC: array<Ball, 8> = array<Ball, 8>(
    Ball(vec4<f32>(2.6, 1.35, 5, 0.34), vec4<f32>(0.35, 0.8, 1, 3.2)),
    Ball(vec4<f32>(-4.2, 1.35, 2.2, 0.34), vec4<f32>(0.35, 0.8, 1, 3.2)),
    Ball(vec4<f32>(-8.6, 1.35, -3.4, 0.34), vec4<f32>(0.35, 0.8, 1, 3.2)),
    Ball(vec4<f32>(-3, 1.35, -8.8, 0.34), vec4<f32>(0.35, 0.8, 1, 3.2)),
    Ball(vec4<f32>(5.4, 1.35, -7.2, 0.34), vec4<f32>(0.35, 0.8, 1, 3.2)),
    Ball(vec4<f32>(10.2, 1.35, -1, 0.34), vec4<f32>(0.35, 0.8, 1, 3.2)),
    Ball(vec4<f32>(4, 1.35, 8.4, 0.34), vec4<f32>(0.35, 0.8, 1, 3.2)),
    Ball(vec4<f32>(-9, 1.35, 9.6, 0.34), vec4<f32>(0.35, 0.8, 1, 3.2)),
);

struct Hit {
    t: f32,
    n: vec3<f32>,
    albedo: vec3<f32>,
    emissive: f32,
};

fn rot_y(p: vec3<f32>, c: f32, s: f32) -> vec3<f32> {
    return vec3<f32>(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

// A box rotated about y: move the ray into the box's frame, slab test, and
// rotate the normal back. Rotations keep t, so no rescaling is needed.
fn hit_box(ro: vec3<f32>, rd: vec3<f32>, b: Box, limit: f32) -> f32 {
    // The bounding sphere first (rd is unit length): most boxes are missed,
    // behind the ray or beyond the nearest hit, and need no slab test.
    let oc = b.c.xyz - ro;
    let r2 = dot(b.h.xyz, b.h.xyz);
    let tca = dot(oc, rd);
    let d2 = dot(oc, oc) - tca * tca;
    if (d2 > r2) { return -1.0; }
    let r = sqrt(r2);
    if (tca + r < 0.0 || tca - r > limit) { return -1.0; }
    let co = b.c.w;
    let si = b.h.w;
    let lc = rot_y(ro - b.c.xyz, co, si);
    let ld = rot_y(rd, co, si);
    let inv = vec3<f32>(1.0 / ld.x, 1.0 / ld.y, 1.0 / ld.z);
    let a = (-b.h.xyz - lc) * inv;
    let z = (b.h.xyz - lc) * inv;
    let lo = min(a, z);
    let hi = max(a, z);
    let tmin = max(max(lo.x, lo.y), lo.z);
    let tmax = min(min(hi.x, hi.y), hi.z);
    var t = tmin;
    if (t < 0.001) { t = tmax; }
    if (t < 0.001 || t > limit || tmax < tmin) { return -1.0; }
    return t;
}

fn box_normal(ro: vec3<f32>, rd: vec3<f32>, t: f32, b: Box) -> vec3<f32> {
    let lc = rot_y(ro - b.c.xyz, b.c.w, b.h.w);
    let ld = rot_y(rd, b.c.w, b.h.w);
    let p = lc + ld * t;
    let q = abs(p / b.h.xyz);
    var n = vec3<f32>(0.0, 1.0, 0.0);
    if (q.x >= q.y && q.x >= q.z) {
        n = vec3<f32>(sign(p.x), 0.0, 0.0);
    } else if (q.y >= q.z) {
        n = vec3<f32>(0.0, sign(p.y), 0.0);
    } else {
        n = vec3<f32>(0.0, 0.0, sign(p.z));
    }
    return rot_y(n, b.c.w, -b.h.w);
}

fn hit_ball(ro: vec3<f32>, rd: vec3<f32>, b: Ball, limit: f32) -> f32 {
    let oc = ro - b.c.xyz;
    let qa = dot(rd, rd);
    let qb = dot(oc, rd);
    let qc = dot(oc, oc) - b.c.w * b.c.w;
    let disc = qb * qb - qa * qc;
    if (disc < 0.0) { return -1.0; }
    let root = sqrt(disc);
    var t = (-qb - root) / qa;
    if (t < 0.001) { t = (-qb + root) / qa; }
    if (t < 0.001 || t > limit) { return -1.0; }
    return t;
}

fn ground_color(p: vec3<f32>) -> vec3<f32> {
    let d = length(p.xz - vec2<f32>(0.0, 6.0));
    if (d < 5.2) {
        let tile = step(0.5, fract((p.x + p.z) * 0.75));
        return mix(vec3<f32>(0.42, 0.40, 0.36), vec3<f32>(0.50, 0.47, 0.42), tile);
    }
    let road = min(abs(p.x), abs(p.z - 6.0));
    if (road < 1.5) {
        return mix(vec3<f32>(0.40, 0.34, 0.25), vec3<f32>(0.46, 0.39, 0.29),
            step(0.5, fract(p.z * 0.5 + p.x * 0.5)));
    }
    let w = 0.5 + 0.5 * sin(p.x * 0.9) * sin(p.z * 0.7);
    return mix(vec3<f32>(0.13, 0.25, 0.10), vec3<f32>(0.18, 0.31, 0.13), w);
}

fn trace(ro: vec3<f32>, rd: vec3<f32>, far: f32) -> Hit {
    var best = Hit(far, vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0), 0.0);
    if (rd.y < -0.0001) {
        let t = -ro.y / rd.y;
        if (t > 0.001 && t < best.t) {
            best.t = t;
            best.n = vec3<f32>(0.0, 1.0, 0.0);
            best.albedo = ground_color(ro + rd * t);
            best.emissive = 0.0;
        }
    }
    for (var i = 0u; i < BOX_COUNT; i = i + 1u) {
        let b = scene.boxes[i];
        let t = hit_box(ro, rd, b, best.t);
        if (t > 0.0) {
            best.t = t;
            best.n = box_normal(ro, rd, t, b);
            best.albedo = b.col.rgb;
            best.emissive = b.col.w;
        }
    }
    for (var i = 0u; i < BALL_COUNT; i = i + 1u) {
        let b = scene.balls[i];
        let t = hit_ball(ro, rd, b, best.t);
        if (t > 0.0) {
            best.t = t;
            best.n = normalize(ro + rd * t - b.c.xyz);
            best.albedo = b.col.rgb;
            best.emissive = b.col.w;
        }
    }
    let mask = u32(u.misc.x);
    for (var i = 0u; i < ORB_COUNT; i = i + 1u) {
        if ((mask & (1u << i)) != 0u) { continue; }
        let b = scene.orbs[i];
        let t = hit_ball(ro, rd, b, best.t);
        if (t > 0.0) {
            best.t = t;
            best.n = normalize(ro + rd * t - b.c.xyz);
            best.albedo = b.col.rgb;
            best.emissive = b.col.w;
        }
    }
    return hit_pendulums(ro, rd, hit_lamps(ro, rd, best));
}

// The lamps: a ring around the plaza that blinks once a second of village
// time, every lamp at the same moment. What you see of a lamp is light that
// left it d / c ago, so with c a few metres a second the ring blinks as a
// wave, nearest last; walking toward a lamp you meet its flashes sooner
// (they come faster), walking away later (slower).
const LAMP_COUNT: u32 = 12u;
const LAMP_RING: f32 = 6.6;

fn lamp_base(i: u32) -> vec3<f32> {
    // Half a step off the axes, so no lamp stands on a road.
    let a = (f32(i) + 0.5) * 6.2831853 / f32(LAMP_COUNT);
    return vec3<f32>(LAMP_RING * cos(a), 0.0, 6.0 + LAMP_RING * sin(a));
}

// The glow of a lamp at village time t: on for the first 0.3 s of each second.
fn lamp_glow(t: f32) -> f32 {
    if (fract(t) < 0.3) { return 4.0; }
    return 0.06;
}

fn hit_lamps(ro: vec3<f32>, rd: vec3<f32>, best_in: Hit) -> Hit {
    var best = best_in;
    let c_light = u.gamma.y * u.gamma.z;
    for (var i = 0u; i < LAMP_COUNT; i = i + 1u) {
        let base = lamp_base(i);
        let post = Box(vec4<f32>(base.x, 1.0, base.z, 1.0), vec4<f32>(0.06, 1.0, 0.06, 0.0),
            vec4<f32>(0.10, 0.10, 0.12, 0.0));
        let tp = hit_box(ro, rd, post, best.t);
        if (tp > 0.0) {
            best.t = tp;
            best.n = box_normal(ro, rd, tp, post);
            best.albedo = post.col.rgb;
            best.emissive = 0.0;
        }
        let head = Ball(vec4<f32>(base.x, 2.15, base.z, 0.26), vec4<f32>(1.0, 0.82, 0.50, 0.0));
        let th = hit_ball(ro, rd, head, best.t);
        if (th > 0.0) {
            best.t = th;
            best.n = normalize(ro + rd * th - head.c.xyz);
            best.albedo = head.col.rgb;
            // The light reaching the eye now left the lamp th / c ago.
            best.emissive = lamp_glow(u.eye.w - th / c_light);
        }
    }
    return best;
}

// A pendulum wave west of the stall: a frame along z with eight pendulums
// swinging across it (in x). Pendulum n makes 20 + n swings every 60 s of
// village time (periods 2.2 to 3 s, lengths 1.2 to 2.2 m), so their phases
// drift apart and come back together every minute. Each is drawn as it was d / c ago (d to its pivot, which is within
// a metre of the bob), so the nearer ones lag the farther ones, and moving
// along the row speeds the swings up ahead of you and slows them behind.
const PEND_COUNT: u32 = 8u;
const PEND_X: f32 = -2.2;
const PEND_TOP: f32 = 3.2;
const PEND_Z0: f32 = 1.75;
const PEND_CYCLE: f32 = 60.0;
const PEND_AMP: f32 = 0.45;

// The capsule from pa to pb of radius r: its nearest hit before `limit`.
fn hit_capsule(ro: vec3<f32>, rd: vec3<f32>, pa: vec3<f32>, pb: vec3<f32>, r: f32,
    limit: f32) -> f32 {
    let ba = pb - pa;
    let oa = ro - pa;
    let baba = dot(ba, ba);
    let bard = dot(ba, rd);
    let baoa = dot(ba, oa);
    let rdoa = dot(rd, oa);
    let oaoa = dot(oa, oa);
    let a = baba - bard * bard;
    let b = baba * rdoa - baoa * bard;
    let c = baba * oaoa - baoa * baoa - r * r * baba;
    let h = b * b - a * c;
    if (h < 0.0) { return -1.0; }
    let t = (-b - sqrt(h)) / a;
    let y = baoa + t * bard;
    if (y > 0.0 && y < baba) {
        if (t > 0.001 && t < limit) { return t; }
        return -1.0;
    }
    // An end cap.
    let oc = select(ro - pb, oa, y <= 0.0);
    let bb = dot(rd, oc);
    let cc = dot(oc, oc) - r * r;
    let hh = bb * bb - cc;
    if (hh < 0.0) { return -1.0; }
    let t2 = -bb - sqrt(hh);
    if (t2 > 0.001 && t2 < limit) { return t2; }
    return -1.0;
}

fn capsule_normal(p: vec3<f32>, pa: vec3<f32>, pb: vec3<f32>) -> vec3<f32> {
    let ba = pb - pa;
    let k = clamp(dot(p - pa, ba) / dot(ba, ba), 0.0, 1.0);
    return normalize(p - (pa + ba * k));
}

// Whether the ray meets the box lo..hi before `limit` (the installation's
// bounds, so most rays skip it).
fn meets_aabb(ro: vec3<f32>, rd: vec3<f32>, lo: vec3<f32>, hi: vec3<f32>, limit: f32) -> bool {
    let inv = vec3<f32>(1.0) / rd;
    let a = (lo - ro) * inv;
    let z = (hi - ro) * inv;
    let tmin = max(max(min(a.x, z.x), min(a.y, z.y)), min(a.z, z.z));
    let tmax = min(min(max(a.x, z.x), max(a.y, z.y)), max(a.z, z.z));
    return tmax >= max(tmin, 0.0) && tmin < limit;
}

fn hit_pendulums(ro: vec3<f32>, rd: vec3<f32>, best_in: Hit) -> Hit {
    var best = best_in;
    let z1 = PEND_Z0 + f32(PEND_COUNT - 1u) + 0.5;
    if (!meets_aabb(ro, rd, vec3<f32>(PEND_X - 1.3, 0.2, PEND_Z0 - 0.6),
        vec3<f32>(PEND_X + 1.3, PEND_TOP + 0.2, z1 + 0.1), best.t)) {
        return best;
    }
    let wood = vec3<f32>(0.30, 0.20, 0.12);
    let zc = (PEND_Z0 - 0.5 + z1) * 0.5;
    let hz = (z1 - PEND_Z0 + 0.5) * 0.5;
    var frame: array<Box, 3>;
    frame[0] = Box(vec4<f32>(PEND_X, PEND_TOP + 0.07, zc, 1.0), vec4<f32>(0.08, 0.08, hz, 0.0),
        vec4<f32>(wood, 0.0));
    frame[1] = Box(vec4<f32>(PEND_X, (PEND_TOP + 0.1) * 0.5, PEND_Z0 - 0.5, 1.0),
        vec4<f32>(0.08, (PEND_TOP + 0.1) * 0.5, 0.08, 0.0), vec4<f32>(wood, 0.0));
    frame[2] = Box(vec4<f32>(PEND_X, (PEND_TOP + 0.1) * 0.5, z1, 1.0),
        vec4<f32>(0.08, (PEND_TOP + 0.1) * 0.5, 0.08, 0.0), vec4<f32>(wood, 0.0));
    for (var k = 0u; k < 3u; k = k + 1u) {
        let t = hit_box(ro, rd, frame[k], best.t);
        if (t > 0.0) {
            best.t = t;
            best.n = box_normal(ro, rd, t, frame[k]);
            best.albedo = wood;
            best.emissive = 0.0;
        }
    }
    let c_light = u.gamma.y * u.gamma.z;
    for (var i = 0u; i < PEND_COUNT; i = i + 1u) {
        let pivot = vec3<f32>(PEND_X, PEND_TOP, PEND_Z0 + f32(i));
        let period = PEND_CYCLE / (20.0 + f32(i));
        // The length that swings with this period: L = g (T / 2 pi)^2.
        let len = 9.81 * pow(period / 6.2831853, 2.0);
        // The time the light now arriving left it, and its angle then.
        let te = u.eye.w - length(pivot - ro) / c_light;
        let ang = PEND_AMP * sin(6.2831853 * te / period);
        let bob = pivot + len * vec3<f32>(sin(ang), -cos(ang), 0.0);
        let tr = hit_capsule(ro, rd, pivot, bob, 0.025, best.t);
        if (tr > 0.0) {
            best.t = tr;
            best.n = capsule_normal(ro + rd * tr, pivot, bob);
            best.albedo = vec3<f32>(0.25, 0.25, 0.28);
            best.emissive = 0.0;
        }
        let tb = hit_ball(ro, rd, Ball(vec4<f32>(bob, 0.17), vec4<f32>(0.0)), best.t);
        if (tb > 0.0) {
            best.t = tb;
            best.n = normalize(ro + rd * tb - bob);
            best.albedo = vec3<f32>(0.85, 0.62, 0.22);
            best.emissive = 0.0;
        }
    }
    return best;
}

fn occluded(ro: vec3<f32>, rd: vec3<f32>) -> bool {
    for (var i = 0u; i < BOX_COUNT; i = i + 1u) {
        if (hit_box(ro, rd, scene.boxes[i], 48.0) > 0.0) { return true; }
    }
    for (var i = 0u; i < BALL_COUNT; i = i + 1u) {
        if (hit_ball(ro, rd, scene.balls[i], 48.0) > 0.0) { return true; }
    }
    return false;
}

fn sky(rd: vec3<f32>) -> vec3<f32> {
    let h = clamp(rd.y * 1.5 + 0.06, 0.0, 1.0);
    var c = mix(vec3<f32>(0.60, 0.70, 0.84), vec3<f32>(0.13, 0.30, 0.62), h);
    let sd = max(dot(rd, normalize(u.sun.xyz)), 0.0);
    c = c + vec3<f32>(1.0, 0.90, 0.70) * pow(sd, 420.0) * 7.0;
    c = c + vec3<f32>(1.0, 0.82, 0.58) * pow(sd, 9.0) * 0.12;
    return c;
}

fn shade(ro: vec3<f32>, rd: vec3<f32>, h: Hit) -> vec3<f32> {
    if (h.t >= 399.0) { return sky(rd); }
    let sun_dir = normalize(u.sun.xyz);
    let ndl = max(dot(h.n, sun_dir), 0.0);
    var lit = 0.0;
    if (ndl > 0.0 && !occluded(ro + h.n * 0.02, sun_dir)) { lit = ndl; }
    let amb = 0.55 + 0.45 * clamp(h.n.y, 0.0, 1.0);
    var c = h.albedo * (vec3<f32>(0.34, 0.41, 0.55) * amb * 0.55
        + vec3<f32>(1.0, 0.93, 0.80) * u.sun.w * lit);
    c = c + h.albedo * h.emissive * 2.2;
    let haze = 1.0 - exp(-h.t * 0.0055);
    return mix(c, sky(rd), haze * 0.55);
}

// The colour shift: a blackbody gain (the light's temperature is multiplied
// by D) and a chroma bias that saturates about one and a half octaves out.
fn blackbody(k: f32) -> vec3<f32> {
    let t = clamp(k, 1000.0, 40000.0) / 100.0;
    var r = 1.0;
    var g = 1.0;
    var b = 1.0;
    if (t <= 66.0) {
        g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0);
    } else {
        r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0);
        g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0);
    }
    if (t >= 66.0) {
        b = 1.0;
    } else if (t > 19.0) {
        b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0);
    } else {
        b = 0.0;
    }
    return vec3<f32>(r, g, b);
}

fn doppler_color(c: vec3<f32>, d: f32) -> vec3<f32> {
    let s = clamp(log2(max(d, 0.01)), -8.0, 8.0);
    let gain = blackbody(5800.0 * exp2(s)) / max(blackbody(5800.0), vec3<f32>(0.05));
    var out = c * gain;
    let k = clamp(abs(s) / 1.4, 0.0, 1.0) * 0.55;
    let target = select(vec3<f32>(0.90, 0.09, 0.02), vec3<f32>(0.30, 0.30, 1.0), s >= 0.0);
    let lum = max(dot(out, vec3<f32>(0.2126, 0.7152, 0.0722)), 0.0);
    out = mix(out, target * (0.30 + lum), k);
    return max(out, vec3<f32>(0.0));
}

// The observed direction d (in the moving frame) as seen from the world:
// a Lorentz boost of the photon four-momentum, normalised.
fn aberrate(d: vec3<f32>, beta: vec3<f32>) -> vec3<f32> {
    let b2 = dot(beta, beta);
    if (b2 < 1e-8) { return d; }
    return normalize(d + ((u.gamma.x - 1.0) / b2) * dot(beta, d) * beta + u.gamma.x * beta);
}

// Sampling the contracted world: stretch the ray's component along the
// motion by gamma, which is the inverse of the length contraction the
// observer sees.
fn contract_dir(d: vec3<f32>, beta: vec3<f32>) -> vec3<f32> {
    let b2 = dot(beta, beta);
    if (b2 < 1e-8) { return d; }
    let bh = beta * inverseSqrt(b2);
    return normalize(d + (u.gamma.x - 1.0) * dot(d, bh) * bh);
}

// `init` copies the constants into the storage buffer once, the first
// frame; every ray then reads the buffer. Indexing a const array with a
// variable rebuilds the whole array per access in the Metal translation,
// which cost most of the frame when each thread did it.
@compute @workgroup_size(64)
fn init(@builtin(local_invocation_index) li: u32) {
    if (li < BOX_COUNT) { scene.boxes[li] = BOXES_SRC[li]; }
    if (li < BALL_COUNT) { scene.balls[li] = BALLS_SRC[li]; }
    if (li < ORB_COUNT) { scene.orbs[li] = ORBS_SRC[li]; }
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let size = vec2<f32>(u.misc.y, u.misc.z);
    if (f32(id.x) >= size.x || f32(id.y) >= size.y) { return; }
    let uv = (vec2<f32>(f32(id.x), f32(id.y)) + 0.5) / size;
    let ndc = uv * 2.0 - 1.0;
    let th = u.forward.w;
    let d0 = normalize(u.forward.xyz + ndc.x * th * u.right.w * u.right.xyz
        - ndc.y * th * u.up.xyz);

    var dw = d0;
    if (u.effects.y > 0.5) { dw = aberrate(d0, u.beta.xyz); }
    var dc = dw;
    if (u.effects.w > 0.5) { dc = contract_dir(dw, u.beta.xyz); }

    let ro = u.eye.xyz;
    let hit = trace(ro, dc, 400.0);
    var radiance = shade(ro, dc, hit);

    let d = u.gamma.x * (1.0 + dot(u.beta.xyz, dw));
    if (u.effects.z > 0.5) { radiance = radiance * clamp(d * d * d, 0.0, 24.0); }
    if (u.effects.x > 0.5) { radiance = doppler_color(radiance, d); }

    film[id.y * u32(size.x) + id.x] = vec4<f32>(radiance, 1.0);
}
