# terrain: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

Works. `volec main.vl -o terrain` builds with std only. Headless mode prints checks; windowed mode is the fly-over.

- Noise (GPU compute). `./terrain --headless` through gpu-run: min 0.000, max 1.000, mean 0.557, 9.9% under sea level. Checks: range within [0,1], spread > 0.5, 5% to 60% under sea level.
- LOD. Per camera, blocks per step and triangles are printed and checked against (16/step)^2 * 2 per block. Camera 1: 22/47/118/69 blocks at steps 1/2/4/8, 21608 triangles. Camera 2: 0/4/53/199, 3800 triangles. Camera 3: 26/56/126/48, 24896 triangles. All 256 blocks drawn in each.
- Shadows. The same view with the shadow lookup on and off: 2.5%, 2.0%, 5.9% of pixels darkened for cameras 1-3 (check 0.5% to 60%). This shows the shadow pass affects the picture; I did not check shadow placement against geometry.
- Shots. `--cam N --shot FILE.ppm` for cameras 1-3, converted to PNG; I looked at all three. Camera 2 (overview) reads well: island, snow, sea, beach. Camera 1 (valley): grass, rock, snow, fog. Camera 3 (cliff over water) had shadow acne, reduced by raising the bias from 0.0008 to 0.0025.
- `volec test main.vl`: 7 tests pass at -O0 and -O2 (matrices, LOD thresholds, template sizes, index range and triangle count).
- Windowed: `./terrain --frames 120` through gpu-run ran and exited 0. The display was asleep or occluded, so frames came from the 10 fps timer (stderr said so). I did not see the window and did not measure frame times.

Not done or broken:
- LOD seams: neighbouring blocks at different steps leave cracks (no skirts or stitching).
- No frustum culling; the index list is rebuilt on the CPU each frame (up to ~1.5 MB).
- Water has no shadows or reflections. Controls: none beyond closing the window.

## 2. How you worked

- `volec guide` (full, gpu, window) and `guide --find` (~6 calls). The full guide and gpu section were enough to start.
- `volec query items` and `query show` (~15 calls) for std's API (std::gpu, std::fs, std::env, RenderDesc::depth, PassDesc::color, set_index_buffer, draw_indexed). Most useful tool: one line per signature question. I did not use `query context`.
- `volec test` (3 runs), `volec check`, `volec main.vl -o` (~25 builds). Builds took 0.3 to 0.8 s.
- The check hook ran after each Write and applied two `&` fixes itself (lent inout arguments), which saved two turns.
- I did not use `volec edit`, `refactor` or the Edit tool. I rewrote .vl files with small Python string-replace scripts and whole-file Write calls. Python was faster for multi-line edits, but it skips the checked-edit path those tools exist for. I should have weighed that more.
- tools/agent-feedback: 4 lines recorded.
- GPU runs: about 12 through gpu-run; waits 0 to 79 s; load 1.8 to 24.9.
- Scratch programs outside my folder (scratchpad) for two diagnoses: about five builds and runs.
- Failed builds and turns: first build had 3 test errors (`Gpa::default` does not exist; tests take `gpa: Gpa`; a `*k` deref on u32), a `[u8]` vs `str` mismatch, a `[f64; 3]` vs `[f32; 3]` literal, a sink move out of a reference (2 errors), and 3 lent-inout markers (2 auto-fixed). About 4 failed build rounds in total.
- GPU runs that failed: 2 (the inline-shader problem and the water bind layout), plus one `[u8]`/`str` path error caught without a GPU run. About 15 turns went to the two GPU problems.

## 3. What went well

- Discoverable std API: `query items` and `query show` gave exact signatures with defaults.
- Concrete errors: `cannot move 'dev' (Device) out of a reference` and `'sc' is lent inout here: mark it '&sc'` each took one edit.
- Short compile times; `volec test` runs -O0 and -O2.
- fluid2d was a good model for the frame loop and headless path; the depth_only shadow pattern from the guide worked unchanged.
- The gpu.layout message states the rule, and the fix (a separate module) was clear once read.
- CPU-side mesh and LOD logic was testable at once.

## 4. What went badly

1. Shader temporaries lose their entry points (compiler or std bug). Minimal repro, one file:
   `let p1 = dev.compute_pipeline(dev.shader_wgsl(NOISE)?, "main")?;`
   gives `gpu: the pipeline was rejected: no compute entry point 'main' in the shader`. With `let sh = dev.shader_wgsl(NOISE)?;` first, it works. In my full program the same failure appeared once as `vs_shadow` and once as `main`, which looked random until the scratch probes. The guide's examples always let-bind the shader, and I found no rule saying so.

2. Bind layouts take bindings from other entry points of the same module. The water pipeline (vs_water, fs_water) in a module with the terrain's vs and fs got bindings 0, 1 and 2, and its one-entry group failed:
   `scene.vl:104:23: gpu.layout: the layout has 3 bindings, 0, 1 and 2, and the bind group does not fit them ...`
   The depth-only pipeline in the same module got only 0 and 1, so the rule is not "this pipeline's entry points only". Moving water to its own module fixed it. The guide's sentence about "a second entry point of the same module" hints at this but does not say it.

3. WGSL in string literals. About 170 lines as `"...\n\` continuation lines are hard to write and edit; a stray or missing `\` breaks the shader far from the cause. Raw or multi-line strings, or shader files embedded by the compiler, would help on every edit.

4. String literal types. `var shot_path = "";` then `shot_path = a;` (a from env::args()) gave `'[u8]' where 'str' goes`. Declaring the var `[u8]` and assigning `a.as_bytes()` fixed it. The guide's line "a string literal is one where a str goes, and a str goes where a [u8] does" is right, but the error points at the variable and I did not expect that.

5. `volec test a.vl b.vl` gives `one ROOT at most`. Testing one root that mods the others works; the usage line does not say so.

6. Float literal inference: `let center = [128.0, 20.0, 128.0];` is `[f64; 3]`, and passing it to a `[f32; 3]` parameter fails. The message is good and `volec fix --suggested` gives the annotation, but it is an easy trap in numeric code.

7. Tests take the allocator as a parameter (`#[test] fn x(gpa: Gpa)`). The error explains it; it is new to me.

8. Closures in render passes capture `self` and its fields. It compiled and ran, so capture by reference works; I did not test it further.

9. Shader errors appear only at run time: `dev.shader_wgsl` and the pipeline constructors report at the GPU call. A compile-time WGSL check would catch these earlier.

10. `--frames` in windowed mode prints nothing when the display is asleep; the only sign is one stderr line after 3 s, so an agent cannot tell whether anything was drawn.

## 5. The language

What fought me:
- Handle ownership: a Device or Queue passed to a constructor needs `sink` (the error says so), but the choice of sink, let or copy is not obvious for a handle type.
- inout: `&x` at the call site is easy to forget. Method receivers need no `&` (`self.mesh.select(...)`), but a field passed to a free inout function does. The rule is consistent, but I hit it three times.
- Literal defaults (f64, i64) and the `[u8]`/`str` split cost two turns.
- No `Default` for `Gpa`; tests receive one. Both sensible, both new.

What I liked:
- Value semantics made the GPU object graph easy to follow: each pipeline, bind group and buffer is a plain value, dropped at scope end.
- `for c in self.mesh.chunks.iter()` with `pass.draw_indexed` inside a closure reads well.
- `if` as an expression, `?`, and `match` on `app.wait()` kept the window loop short.
- The explicit allocator was never in the way once functions took `gpa`.

## 6. Suggestions, ranked by time saved

1. Fix or document the shader-temporary bug (repro in 4.1). Better, a compute_pipeline error that says "the shader is a temporary: let-bind it" when the entry is missing. Saves about 15 turns and two GPU runs.
2. Limit a pipeline's bind layout to its own entry points' bindings, or have `gpu.layout` name the other entry point that added the binding. Saves 3 to 5 turns and one GPU run.
3. Multi-line strings, or shader files embedded by the compiler, for WGSL. Every shader edit currently needs escaping.
4. Type-check WGSL at compile time, with a line error, so a bad shader fails before any GPU run.
5. Let a path come from a str without the variable-type trap (`File::create(path: str)`, or a str-typed var from a literal).
6. A `volec query` answer for "what does this pipeline's layout contain".
7. One guide sentence on handles (Device, Queue, Buffer, Texture): when to take them sink, let or copied.

Notes: `query context` was not used; `edit patch` and the Edit tool were not used (Python rewrites instead). The windowed mode was not seen on screen.
