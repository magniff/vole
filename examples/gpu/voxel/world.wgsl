struct Params { seed: vec4<f32> }
struct Info { chunk: vec4<f32> }
struct Vertex { pos: vec4<f32>, normal: vec4<f32>, color: vec4<f32> }
struct Edit { data: vec4<f32>, kind: vec4<f32> }
@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<uniform> info: Info;
@group(0) @binding(2) var<storage, read_write> density: array<f32>;
@group(0) @binding(3) var<storage, read_write> offsets: array<u32>;
@group(0) @binding(4) var<storage, read_write> vertices: array<Vertex>;
@group(0) @binding(5) var<storage, read_write> meta: array<atomic<u32>>;
@group(0) @binding(6) var<storage, read_write> water: array<Vertex>;
@group(0) @binding(7) var<storage, read_write> plants: array<Vertex>;
@group(0) @binding(8) var<storage, read> edits: array<Edit>;
const N: u32 = 32u;
const H: u32 = 48u;
const WATER: f32 = 12.0;
const MAX_FACES: u32 = 12288u;
fn hash2(x: i32, z: i32) -> f32 {
    var n = u32(x) * 374761393u + u32(z) * 668265263u + u32(params.seed.x) * 1442695041u;
    n = (n ^ (n >> 13u)) * 1274126177u;
    n = n ^ (n >> 16u);
    return f32(n & 0x00ffffffu) / 16777215.0;
}
fn noise2(x: f32, z: f32) -> f32 {
    let ix = i32(floor(x));
    let iz = i32(floor(z));
    var fx = x - floor(x);
    var fz = z - floor(z);
    fx = fx * fx * (3.0 - 2.0 * fx);
    fz = fz * fz * (3.0 - 2.0 * fz);
    let a = hash2(ix, iz);
    let b = hash2(ix + 1, iz);
    let c = hash2(ix, iz + 1);
    let d = hash2(ix + 1, iz + 1);
    return mix(mix(a, b, fx), mix(c, d, fx), fz);
}
fn fbm(x: f32, z: f32) -> f32 {
    var sum = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i = 0; i < 5; i += 1) {
        sum += noise2(x * frequency, z * frequency) * amplitude;
        frequency *= 2.03;
        amplitude *= 0.5;
    }
    return sum;
}
fn height(x: f32, z: f32) -> f32 {
    let warp_x = noise2(x * 0.009 + 17.0, z * 0.009 + 3.0) - 0.5;
    let warp_z = noise2(x * 0.009 - 8.0, z * 0.009 + 29.0) - 0.5;
    let wx = x + warp_x * 34.0;
    let wz = z + warp_z * 34.0;
    let broad = fbm(wx * 0.009, wz * 0.009);
    let detail = fbm(wx * 0.035 + 40.0, wz * 0.035 - 20.0);
    let ridge_noise = noise2(wx * 0.014 + 70.0, wz * 0.014 - 30.0);
    let ridge = pow(1.0 - abs(ridge_noise * 2.0 - 1.0), 3.0);
    return 4.0 + broad * 15.0 + detail * 7.0 + ridge * ridge * 20.0;
}
fn apply_edits(x: f32, y: f32, z: f32, initial: f32) -> f32 {
    var d = initial;
    for (var i = 0u; i < u32(params.seed.y); i += 1u) {
        let edit = edits[i];
        let distance = length(vec3<f32>(x, y, z) - edit.data.xyz);
        if distance < edit.data.w {
            if edit.kind.x < 0.5 { d = min(d, distance - edit.data.w); }
            else { d = max(d, edit.data.w - distance); }
        }
    }
    return d;
}
fn density_from_height(x: i32, y: i32, z: i32, h: f32) -> f32 {
    var d = h - f32(y) - 0.5;
    if y > 3 {
        let cave = abs(sin(f32(x) * 0.13 + sin(f32(z) * 0.09))
            + sin(f32(z) * 0.17 - f32(y) * 0.11) + sin(f32(y) * 0.19 + f32(x) * 0.07));
        d = min(d, (cave - 0.48) * 5.0);
    }
    return apply_edits(f32(x), f32(y), f32(z), d);
}
fn world_density(x: i32, y: i32, z: i32) -> f32 {
    if y < 0 { return 10.0; }
    if y >= 48 { return -10.0; }
    return density_from_height(x, y, z, height(f32(x), f32(z)));
}
fn index(x: u32, y: u32, z: u32) -> u32 { return (y * N + z) * N + x; }
fn solid(x: i32, y: i32, z: i32, base: vec3<i32>) -> bool {
    if x >= 0 && x < 32 && y >= 0 && y < 48 && z >= 0 && z < 32 {
        return density[index(u32(x), u32(y), u32(z))] > 0.0;
    }
    return world_density(base.x + x, base.y + y, base.z + z) > 0.0;
}
@compute @workgroup_size(8, 8)
fn terrain(@builtin(global_invocation_id) gid: vec3<u32>) {
    if gid.x >= N || gid.y >= N { return; }
    let wx = i32(info.chunk.x) * 32 + i32(gid.x);
    let wz = i32(info.chunk.y) * 32 + i32(gid.y);
    let h = height(f32(wx), f32(wz));
    for (var y = 0u; y < H; y += 1u) {
        density[index(gid.x, y, gid.y)] = density_from_height(wx, i32(y), wz, h);
    }
}
var<workgroup> scan: array<u32, 256>;
fn face_count(x: i32, y: i32, z: i32, base: vec3<i32>) -> u32 {
    if !solid(x, y, z, base) { return 0u; }
    var count = 0u;
    if !solid(x + 1, y, z, base) { count += 1u; }
    if !solid(x - 1, y, z, base) { count += 1u; }
    if !solid(x, y + 1, z, base) { count += 1u; }
    if !solid(x, y - 1, z, base) { count += 1u; }
    if !solid(x, y, z + 1, base) { count += 1u; }
    if !solid(x, y, z - 1, base) { count += 1u; }
    return count;
}
fn biome(x: f32, z: f32, y: f32, normal_y: f32) -> vec3<f32> {
    let h = height(x, z);
    let moisture = noise2(x * 0.013 + 90.0, z * 0.013 - 40.0);
    var color = vec3<f32>(0.28, 0.43, 0.16);
    if moisture > 0.57 { color = vec3<f32>(0.12, 0.29, 0.12); }
    if h < WATER + 0.5 { color = vec3<f32>(0.68, 0.59, 0.36); }
    if h > 22.0 || normal_y < 0.5 { color = vec3<f32>(0.42, 0.41, 0.40); }
    if h > 33.0 && normal_y > 0.5 { color = vec3<f32>(0.82, 0.87, 0.91); }
    let variation = 0.88 + 0.20 * noise2(x * 0.7, z * 0.7);
    return color * variation;
}
fn biome_id(x: f32, z: f32) -> f32 {
    let h = height(x, z);
    if h > 33.0 { return 4.0; }
    if h > 22.0 { return 3.0; }
    if h < WATER + 0.5 { return 2.0; }
    if noise2(x * 0.013 + 90.0, z * 0.013 - 40.0) > 0.57 { return 1.0; }
    return 0.0;
}
fn put(vertex_index: u32, p: vec3<f32>, n: vec3<f32>, color: vec3<f32>, material: f32) {
    if vertex_index < MAX_FACES * 6u {
        vertices[vertex_index].pos = vec4<f32>(p, 1.0);
        vertices[vertex_index].normal = vec4<f32>(n, 0.0);
        vertices[vertex_index].color = vec4<f32>(color, material);
    }
}
fn emit_quad(at_face: u32, orientation: u32, p: vec3<f32>, n: vec3<f32>, color: vec3<f32>) {
    let at = at_face * 6u;
    var a = vec3<f32>(0.0);
    var b = vec3<f32>(1.0);
    var c = vec3<f32>(1.0);
    var d = vec3<f32>(0.0);
    if orientation == 0u { a = vec3<f32>(1,0,0); b = vec3<f32>(1,1,0); c = vec3<f32>(1,1,1); d = vec3<f32>(1,0,1); }
    if orientation == 1u { a = vec3<f32>(0,0,1); b = vec3<f32>(0,1,1); c = vec3<f32>(0,1,0); d = vec3<f32>(0,0,0); }
    if orientation == 2u { a = vec3<f32>(0,1,1); b = vec3<f32>(1,1,1); c = vec3<f32>(1,1,0); d = vec3<f32>(0,1,0); }
    if orientation == 3u { a = vec3<f32>(0,0,0); b = vec3<f32>(1,0,0); c = vec3<f32>(1,0,1); d = vec3<f32>(0,0,1); }
    if orientation == 4u { a = vec3<f32>(1,0,1); b = vec3<f32>(1,1,1); c = vec3<f32>(0,1,1); d = vec3<f32>(0,0,1); }
    if orientation == 5u { a = vec3<f32>(0,0,0); b = vec3<f32>(0,1,0); c = vec3<f32>(1,1,0); d = vec3<f32>(1,0,0); }
    let v0 = p + a;
    let v1 = p + b;
    let v2 = p + c;
    let v3 = p + d;
    let material = biome_id(p.x, p.z);
    put(at, v0, n, color, material);
    put(at + 1u, v1, n, color, material);
    put(at + 2u, v2, n, color, material);
    put(at + 3u, v0, n, color, material);
    put(at + 4u, v2, n, color, material);
    put(at + 5u, v3, n, color, material);
}
fn water_put(at: u32, p: vec3<f32>, color: vec3<f32>) {
    if at < 6144u {
        water[at].pos = vec4<f32>(p, 1.0);
        water[at].normal = vec4<f32>(0.0, 1.0, 0.0, 0.0);
        water[at].color = vec4<f32>(color, 0.68);
    }
}
fn water_quad(p: vec3<f32>, depth: f32) {
    let face = atomicAdd(&meta[1], 1u);
    let at = face * 6u;
    let shallow = vec3<f32>(0.12, 0.48, 0.56);
    let deep = vec3<f32>(0.035, 0.16, 0.28);
    let color = mix(shallow, deep, clamp(depth / 6.0, 0.0, 1.0));
    let a = p + vec3<f32>(0,0,1);
    let b = p + vec3<f32>(1,0,1);
    let c = p + vec3<f32>(1,0,0);
    let d = p;
    water_put(at, a, color); water_put(at + 1u, b, color); water_put(at + 2u, c, color);
    water_put(at + 3u, a, color); water_put(at + 4u, c, color); water_put(at + 5u, d, color);
}
@compute @workgroup_size(256)
fn mesh(@builtin(local_invocation_id) lid: vec3<u32>) {
    let lane = lid.x;
    let base = vec3<i32>(i32(info.chunk.x) * 32, 0, i32(info.chunk.y) * 32);
    var running = 0u;
    for (var tile = 0u; tile < 192u; tile += 1u) {
        let voxel = tile * 256u + lane;
        let x = i32(voxel % N);
        let z = i32((voxel / N) % N);
        let y = i32(voxel / (N * N));
        let count = face_count(x, y, z, base);
        scan[lane] = count;
        workgroupBarrier();
        for (var step = 1u; step < 256u; step *= 2u) {
            var value = scan[lane];
            if lane >= step { value += scan[lane - step]; }
            workgroupBarrier();
            scan[lane] = value;
            workgroupBarrier();
        }
        offsets[voxel] = running + scan[lane] - count;
        let total = scan[255];
        workgroupBarrier();
        running += total;
        workgroupBarrier();
    }
    if lane == 0u {
        atomicStore(&meta[0], min(running * 6u, MAX_FACES * 6u));
        if running > MAX_FACES { atomicStore(&meta[3], 1u); }
    }
    for (var voxel = lane; voxel < N * N * H; voxel += 256u) {
        let x = i32(voxel % N);
        let z = i32((voxel / N) % N);
        let y = i32(voxel / (N * N));
        if !solid(x, y, z, base) { continue; }
        let p = vec3<f32>(f32(base.x + x), f32(y), f32(base.z + z));
        let color = biome(p.x, p.z, p.y, 1.0);
        var face = 0u;
        if !solid(x + 1, y, z, base) { emit_quad(offsets[voxel] + face, 0u, p, vec3<f32>(1,0,0), biome(p.x,p.z,p.y,0.0)); face += 1u; }
        if !solid(x - 1, y, z, base) { emit_quad(offsets[voxel] + face, 1u, p, vec3<f32>(-1,0,0), biome(p.x,p.z,p.y,0.0)); face += 1u; }
        if !solid(x, y + 1, z, base) { emit_quad(offsets[voxel] + face, 2u, p, vec3<f32>(0,1,0), color); face += 1u; }
        if !solid(x, y - 1, z, base) { emit_quad(offsets[voxel] + face, 3u, p, vec3<f32>(0,-1,0), biome(p.x,p.z,p.y,0.0)); face += 1u; }
        if !solid(x, y, z + 1, base) { emit_quad(offsets[voxel] + face, 4u, p, vec3<f32>(0,0,1), biome(p.x,p.z,p.y,0.0)); face += 1u; }
        if !solid(x, y, z - 1, base) { emit_quad(offsets[voxel] + face, 5u, p, vec3<f32>(0,0,-1), biome(p.x,p.z,p.y,0.0)); }
    }
    for (var cell = lane; cell < N * N; cell += 256u) {
        let wx = base.x + i32(cell % N);
        let wz = base.z + i32(cell / N);
        let h = height(f32(wx), f32(wz));
        if h < WATER { water_quad(vec3<f32>(f32(wx), WATER, f32(wz)), WATER - h); }
    }
    for (var candidate = lane; candidate < 256u; candidate += 256u) {
        let wx = base.x + i32(candidate % 16u) * 2;
        let wz = base.z + i32(candidate / 16u) * 2;
        let h = height(f32(wx), f32(wz));
        let slope = abs(height(f32(wx + 1), f32(wz)) - h) + abs(height(f32(wx), f32(wz + 1)) - h);
        let moisture = noise2(f32(wx) * 0.013 + 90.0, f32(wz) * 0.013 - 40.0);
        let random = hash2(wx, wz);
        let forest = moisture > 0.57 && h > WATER + 0.5 && h < 28.0;
        let tree = slope < 2.0 && ((forest && random > 0.60) || (!forest && random > 0.94));
        let grass = slope < 1.5 && h > WATER + 0.5 && h < 25.0 && random > 0.40;
        if tree || grass {
            let at = atomicAdd(&meta[2], 1u);
            if at < 256u {
                let scale = 0.75 + hash2(wx + 13, wz - 7) * 0.85;
                var kind = 2.0;
                if tree { kind = 1.0; }
                if h < WATER + 0.5 && random > 0.96 { kind = 3.0; }
                let green = mix(vec3<f32>(0.16, 0.36, 0.12), vec3<f32>(0.08, 0.24, 0.10), moisture);
                plants[at].pos = vec4<f32>(f32(wx) + 0.5, h, f32(wz) + 0.5, scale);
                plants[at].color = vec4<f32>(green, kind);
            }
        }
    }
}
