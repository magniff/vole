> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: terrain (procedural fly-over, LOD, shadow map)

## 1. Reproduce
`volec main.vl -o terrain` printed ok, and `volec test main.vl` gave `7 passed (-O0 and -O2 agree)`. Through `gpu-run --timeout 120` at load about 23, `./terrain --headless --cam N --shot shotN.ppm` for N = 1..3 all exited 0 with `checks: all ok`:
- Noise: `min 0.000, max 1.000, mean 0.557, 9.9% under sea level`.
- LOD: 22/47/118/69 blocks and 21608 triangles (camera 1), 0/4/53/199 and 3800 (camera 2), 26/56/126/48 and 24896 (camera 3).
- Shadows: 2.5% / 2.0% / 5.9%.

All three PPMs are byte-identical to the agent's. The pictures:
- Camera 2: an island with snow caps in a blue sea, under fog.
- Camera 1: grass and rock ridges with snowy peaks behind.
- Camera 3: cliffs looming over the water, with submerged terrain visible through the 0.9-alpha sea.

## 2. Claims vs reality
All numbers and statements hold, and the known limits are listed: cracks, no frustum culling, index list rebuilt per frame, no water shadows. Unstated:
- The noise "range" check is satisfied by construction. The kernel clamps to [0, 1] (shaders.vl:43), and min 0.000 / max 1.000 show the clamp is active, so some highs and lows are flattened.
- The README's "7 tests ... index range and triangle count" is accurate.

## 3. Task coverage
- Heightmap from fractal noise generated on the GPU: done (6-octave value-noise fBm plus a ridged term).
- Mesh with distance-based LOD: done (16×16 blocks, steps 1/2/4/8). Cracks are not handled (stated).
- Sun with a shadow map in a depth-only pass: done (3×3 PCF).
- Fog: done.
- Materials by height and slope (grass, rock, snow, plus sand): done.
- Water at sea level: done (blended, Fresnel, glint).
- Headless shots from fixed cameras plus checks (noise range, triangles per LOD): done.
- Fly-over: automatic circle only. No controls, but the task did not ask for any.

## 4. Correctness of the core
- Noise hash, value noise and fBm normalisation are correct. Normals are central differences at full resolution even on coarse blocks, which is good.
- Vertex-pulling from the storage heightmap with index templates (terrain.vl:113-135) is a neat design, and the indices stay in range (tested).
- Shadow: the ortho box covers the island's diagonal (±190 versus 181). Light-space depth is 0..1, matching Metal (math.vl:84-91). The uv y-flip is correct. The bias of 0.0025 depth units is about 1.5 world units, which risks peter-panning; it was chosen against acne.
- Water is drawn after the terrain with depth test on and depth write off. Correct.
- Checks:
  - LOD: `lod_report` (main.vl:55-76) re-derives triangle counts from the same templates, so it checks bookkeeping, not what the GPU drew.
  - Shadows: the on/off comparison shows the shadow map has an effect, not that shadows fall in the right place (admitted).
- The window advances `t += 1/60` per frame (main.vl:210), so flight speed depends on the frame rate.

## 5. Code quality
Sensible modules (math, terrain, scene, shaders, main) with good comments. No `unsafe`. It uses std math (`sqrt`, `tan`, `sin`, `cos`). Issues:
- WGSL duplication: the `U` struct, `HS`, `VOut` and `fog` are repeated in the water module (shaders.vl:128-147). A shared prefix, as deferred did, would avoid it.
- `terrain::HEIGHT` (terrain.vl:17) is unused; the WGSL hard-codes `HS = 60.0` twice.
- The arguments are parsed by hand (main.vl:238-255) and `--cam` is not validated.
- The `noise_shader`/`terrain_shader` wrappers add little.
- `grab` assumes 640×4 bytes is 256-aligned (true only for this width).
- The agent edited with Python string replacement rather than Edit or `volec edit` (its own admission).

## 6. Borrowing
Little. The window loop shape follows fluid2d/life. The depth-only shadow pattern is from `guide gpu`, which is intended. The readback and PPM code are its own (`map_read_copy_in`).

## 6b. New features
- `RenderDesc::depth_only` and `PassDesc::depth_only` for the shadow map (scene.vl:91, 184), used exactly as the guide shows.
- `map_read_copy_in` in `grab` (main.vl:87).
- MRT does not apply.

## 6c. Compiler bug
Hit. The workaround is a `let` for every shader, with a comment (scene.vl:86-92). By its account the bug cost about 15 turns and 2 GPU runs, the costliest item this round. Not counted against it. It also hit a related layout surprise: the water's bind layout picked up the terrain module's bindings, solved by a separate module, about 3-5 turns.

## 7. Tests
Seven tests:
- Matrices: look_at, perspective 0..1, ortho to the unit cube, identity.
- LOD thresholds and template sizes.
- Index range and triangle count.

Good for the CPU maths. Missing: any CPU reference for the noise, the light-space projection of a known point onto the shadow map, and LOD at block boundaries.

## 8. Verdict
Every feature the task listed is present and works, and the GPU-side design is sensible (vertex pulling, depth-only shadow pass). The pictures are plain but correct. The checks are weaker than they look: the range is clamped and the LOD count is self-referential. The report is honest and detailed, including about its own editing habits, and its two GPU-side findings are valuable.

**Grades:** result **B+**, code **B+**, honesty **A-**.
