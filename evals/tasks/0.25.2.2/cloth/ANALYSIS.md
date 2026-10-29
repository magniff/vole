# cloth: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

What works:
- A 64 x 64 PBD cloth on the GPU: predict; a distance solve by colour (stretch and bend, 12 colour kernels per sweep, each projecting its edges in place with the PBD correction split by inverse mass); a collision kernel (sphere, floor, grab); update; GPU normals. The picture: a two-sided lit sheet over a procedural sphere and a checked floor. Builds with `volec main.vl -o cloth`; `volec test main.vl` passes 5 tests (camera ray through centre; flat grid has zero constraint error; stretched grid has its stretch as error; pick returns the particle on the ray; NaN/inf counting).
- Headless (`headless-run.txt`, exit 0, 600 frames):
  - constraint error (rms over all 16000 stretch and bend pairs) 0.0616 at the start, 0.0149 at the end: ok;
  - total energy after frame 120 never above its frame-120 value (47001.7): ok. Kinetic energy peaks at 5440 on impact (frame 60), then decays to about 0;
  - 0 NaN or infinities in 11 reads of positions and velocities;
  - 0.99 ms a frame of GPU time (all submitted, then waited for; gpu-run).
- Grab (`grab-run.txt`, exit 0, 300 frames): the middle particle is dragged to (0.6, 0.2, 0.4) and is 0.0039 away at frame 240. Energy is not judged under grab (the hand does work).
- `shot.png` shows the sheet hanging from its pinned corners, draped over the sphere and resting on the floor.

Not working, or not verified:
- The largest constraint error stays near 0.28 (top row beside the pinned corners, where the sheet's weight goes, and at the sphere). It does not go to zero; the rms does. I used rms for the "falls" verdict.
- Energy is not conserved: PBD turns position corrections into velocity, and the sheet's initial stretch releases on impact (total energy about +10% at frame 60).
- Mouse interaction was not tried by a person. Pick on press and the drag target on move ran only through the headless `--grab`.
- No shader or GPU bug found. I did not inspect the generated MSL.

## 2. How you worked

Commands, roughly:
- `volec guide` (core, gpu, gpu-render, window, testing, `--find`, one search): about 7 calls. The gpu guide's bind-group rule ("a layout holds the bindings the pipeline's own entry points use") mattered most. I used one WGSL module per kernel with a shared prefix, as the fluid2d example does.
- `volec query`: about 12 calls (`items std::gpu`, `show` on RenderDesc::depth, PassDesc::color/with_depth, Device::texture, copy_texture_to_buffer, `items std::window`, and one `grep`). Signatures came fast. The one `grep` (for a Metal detail) did not answer the question.
- `volec check`: the after-write hook ran about 12 times. Its errors were right, and it applied one fix itself (`&enc` on an inout argument, four lines). That saved turns.
- `volec test main.vl`: 6 runs. `volec main.vl -o cloth`: about 20 builds. `volec fmt`: once (dry run, then apply).
- Not used: `volec edit` (I wrote files with direct writes and Python string replacement), `volec fix` (the hook made the one fix), `volec explain`, `volec probe`, `volec refactor`. The query-first hook blocked a plain grep of compiler/std once; `query grep` gave the same information.
- gpu-run: about 20 runs. One run with --timeout 120 queued behind other agents' GPU jobs and my shell's 120 s timeout killed the wait; I cancelled the background job. Other waits were 0 to 42 s.

Time sinks (the physics, about 25 GPU runs and 12 Python analyses; none of it vole):
1. Jacobi with averaging (the brief's option; I chose it without working out its stiffness). Under gravity the sheet stretched to balance its own weight. A pure-Python run of the same scheme with no gravity looked stable and misled me for a while. Over-relaxation (omega 2 did nothing; 3 went NaN). The fix was colour Gauss-Seidel: 12 edge classes (horizontal/vertical, stretch/bend, mod 2 or mod 4), each projected in place, no races.
2. Velocity feedback: solver corrections became velocities, which the next predict extrapolated. Damping 0.999 per substep was not enough; 0.99 was.
3. A flat sheet through the sphere's centre: the sphere can only push sideways in that plane, so the sheet tears across the hole (edge error 16x rest). A 0.25 bulge toward the viewer fixed it.
4. Sweep count: largest error 0.47 (8 sweeps), 0.28 (16), 0.17 (32). I kept 16.

Compile errors: about 12 across the session (below), plus one test error (missing gpa parameter) and one unused import.

## 3. What went well

- Error messages name the fix and the spot: "'enc' is lent inout here: mark it '&enc'"; "expected 'f32', got 'f64' ... 'dt' is 'f64' from its literals ... annotate it, 'dt: f32'"; "unknown field 'pb': did you mean 'xb'".
- `query show` gives exact signatures and the file they live in. The gpu guide's descriptor table is the right density.
- `volec test` runs -O0 and -O2 and checks they agree.
- Build is one command; the binary runs headless with no helper files.
- Std's `Vec` + `as_slice()` + `gpu::bytes_of_f32` was direct for uniforms and readback.
- `pass.dispatch` in closures and bind groups passed by value worked as written.

## 4. What went badly

Compiler and std errors (quoted):
- `error: cannot read build` for `volec build main.vl -o cloth`. The working form is `volec main.vl -o cloth`. No hint.
- `no 'parse_int' in module 'std::num'`, then `undefined variable 'parse_f64'`. parse_int is in the prelude; parse_f64 is std::num::parse_f64. The messages do not say the two differ.
- `expected 'f32', got 'f64'`: correct and the fix is in the text, but I had `let dt = 1.0 / 60.0` used as f32 in several places and the check listed only one site first.
- `no method 'wind_on' on type 'Sim'`: my mistake (I had invented it). The `query items` hint was fine.
- `'enc' is lent inout here (the callee may change it)` when an inout parameter is passed on to another inout function. The hook fixed it. The first line's vocabulary ("lent") is not the one the guide's first-errors table uses.
- `unresolved import 'shaders::SOLVE'` after I removed the constant: correct.
- "changed on disk since you last read it" notices after the hook's own fixes: the notice does not say what changed, so I could not tell whether to re-read.

Guide and docs:
- The gpu guide's bind-group rule and `gpu.layout` example were what I needed. The default for `RenderDesc::depth` (write true, compare Less) I had to take from the signature.
- No example combines a depth-tested draw of a mesh built from `vertex_index` (`draw(0..N)`, no vertex buffer) with a storage buffer read in the vertex stage. gpu-render has depth-only passes and vertex buffers only. I worked it out from the WGSL side.
- I could not find a sentence saying whether dispatches in one compute pass are ordered. Every test behaved as if they were (one pass per dispatch and one pass for all gave identical numbers), but I found no barrier in std's source to confirm it.

GPU and WGSL: no trouble with the uniform layout (vec4-only struct, 176 bytes), `select`, MAP_READ with COPY_DST, or copy_buffer from a COPY_SRC storage buffer. The `Encoder::copy_buffer` method is listed in `query items std::gpu`.

Time sinks vole did not cause: the physics choices in section 2; gpu-run queueing.

## 5. The language

What fought me:
- Passing an inout parameter on to another inout function needs `&`. The hook fixed it; the rule is not in the first-errors table.
- Float literals default to f64. In GPU code almost every literal is f32, so `let dt = 1.0 / 60.0` then `f32` use fails. I wrote `let dt: f32 = ...` after the first error.
- Casts (`as f32`, `as f64`, `as i64`) are clear, but everything needs one.
- Closures inside `compute_pass(|pass| ...)`: I copied handles to locals first, out of caution. I did not test whether that was needed.
- I renamed a field that shared a name with a pipeline field before any compiler error showed it; I did not learn whether vole rejects duplicate field names.
- Tests take `gpa: Gpa` even for pure arithmetic when they allocate (`initial` returns a Vec).

What I liked:
- `f"..."` with `{x:.3e}` and `{x:.4}` read well in the checks.
- `match` on `Option`/`Result` with `Err(e) => { eprintln(..); return 1; }` was the usual shape and had no surprises.
- `inout self` methods on Sim split frame state (`set_frame`), GPU work (`step`) and readback (`read`) cleanly.

## 6. Suggestions, ranked by time saved

1. A guide line on compute dispatch ordering within one pass, and whether std inserts barriers. I spent GPU runs unsure of it.
2. For `volec build`, or any unknown subcommand: a usage hint ("the form is `volec main.vl -o NAME`"). "cannot read build" is a dead end.
3. An f32 literal rule in the gpu guide ("float literals are f64; write `: f32`") and the first-error hint for it. The message is good, but it appears at the first use, not at the `let`.
4. A depth-tested example with a procedural `vertex_index` mesh and a storage buffer in the vertex stage.
5. Hook notices: name the change ("hook changed sim.vl lines 252-258: `&enc`") in the "changed on disk" text.
6. A PBD or cloth example in examples/gpu. (Physics material, not a vole fix; it would have saved the Jacobi detour.)
7. Let `query items` list std methods such as `Encoder::copy_buffer` under the type (they appear in the flat listing; an `impl` lookup would be quicker).

Tool feedback recorded with agent-feedback: volec build form; parse_int vs parse_f64 hints; the sphere-in-plane tear (a physics issue, not vole); the "changed on disk" notice.
