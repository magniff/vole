# ANALYSIS: terrain (vole 0.25.2)

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note.

The harness refused to let me write ANALYSIS.md, so the full analysis is below for the orchestrator to save verbatim. Program, tests and README are in /Users/magniff/workspace/tachyon/evals/tasks/0.25.2/terrain/ (main.vl, mat.vl, mesh.vl, shaders.vl, README.md, shot0.ppm/png, shot1.ppm/png, shot2.ppm/png).

## 1. Result

What works:
- `volec main.vl -o terrain` builds. `volec check` is clean.
- `volec test main.vl`: 5 tests pass at -O0 and -O2 (Newton sqrt, look-at, ortho, the triangle count of every tile and level against 2q^2 + 8q, the LOD thresholds).
- `./terrain --headless` through gpu-run works for all three cameras and every check prints "ok". Noise: 66049 heights, min 0.149, max 0.835, mean 0.490. Overview camera (0): LOD2 19 tiles, LOD3 45 tiles, 6528 terrain triangles. Camera 1 (close, sun side) uses all four levels. Shadow check, from the overview: 16564 of 262144 pixels (6.32%) darker by 10% or more with the shadow map on.
- The shots were viewed. The overview shows sea, grass, rock, snow, fog and cast shadows. Camera 2 shows a lit mountain face. Camera 1 is lit with little shadow in frame.

What does not work or is unverified:
- The windowed mode never printed anything. Three gpu-run attempts were killed by the timeout: `--frames 1` (30 s), `--frames 120` (60 s and 90 s). The first of these also reported 56.8 s of waiting at load 18. Not diagnosed; it may be the window path or the environment. The headless path uses the same `render` function, but the window, surface and event loop are not verified.
- No frame timings: the windowed mode was never measured.

## 2. How you worked

- `volec guide` (full), `volec guide gpu` (full), `volec guide window`, `volec guide testing` (grep only): about 8 lookups.
- `volec query items` and `query show` (about 10 calls) on std::gpu, std::window, std::time, std::cli, and on fluid2d's `main` and `headless`. Enough to write the program. I never used `query refs`, `query context`, `edit` or `refactor`.
- Writing: four files with the Write tool, then Edit for changes. `volec edit patch` for two one-line changes (one failed because the formatter had moved the text).
- Check and build: `volec check` (mostly via the hook), `volec test`, and `volec main.vl -o terrain` about 8 times.
- Blocked commands: the query-first hook blocked my grep, head and `sed -n` on main.vl (460 lines), and once `sed -i` on mesh.vl. Each block cost a turn. I switched to `volec query text` and the Read tool.
- The check hook's auto-fix changed many things while I wrote: `&mut x` to `&x`, `let mut` to `var`, f64 literals to f32, `out` to `&out`. Helpful, but it changed files under me, and the edit tool then reported "changed on disk" for my own edits, which was confusing.
- Recorded with tools/agent-feedback: five lines, plus one correction to an earlier line.

## 3. What went well

- The auto-fixes handled most type and mutability errors. The first real compile after the checks took one fix (`Gpa::new()` in a test; tests take `gpa: Gpa`).
- The GPU API is close enough to wgpu that fluid2d was readable and its patterns carried over: compute pass, `render_pass` closures, `draw_indexed` over one index buffer with no vertex buffer, `Depth32Float` with `texture_depth_2d` and `textureLoad` in WGSL, and a depth-only pass.
- The WGSL front end accepted everything I wrote on the first try (for loops, smoothstep, mix, textureLoad on depth, mat2x2, struct constructors).
- `volec test` ran the `#[test]`s at -O0 and -O2 and they agreed.
- File-level errors were precise ("cannot move 'dev' out of a reference ... take the parameter 'sink'"), and the suggested fix worked the first time.

## 4. What went badly

- Time sink 1, my own bug: `luma(lit.clone(), i)` inside a per-pixel loop, 262144 clones of a 1 MB buffer. It looked like a GPU hang and cost two gpu-run timeouts (120 s each). My first hypothesis (a readback buffer still mapped) was wrong, and I changed two things at once. Lesson: a clone in a loop is invisible to the type system, and nothing warns about it.
- Time sink 2: the windowed hang. Three gpu-run attempts, 30 to 90 s each, no output.
- The query-first hook blocked reading a 460-line file with grep, head and sed. Its message did suggest `volec query text`, which worked, but only after the first block. The rule ("reads .vl source", files under 300 lines allowed) is subtle, and I could not tell from the message which files were allowed.
- Float literals: `let x = 1.0;` is f64, so passing it to an f32 parameter fails with "expected 'f32', got 'f64'". The fix hook corrected these silently. A suffix (`1.0f32`) or an annotation on the guide's first page would help.
- `Gpa::new()` in a test: the error "no associated function 'new' in 'Gpa'" is clear, but the right form (`fn t(gpa: Gpa)`) is in the testing guide, not the first page.
- No float math by name in std that I could find (sqrt, sin, cos): `std::num` showed parse_f64 and bit casts only, in my grep. I wrote a Newton sqrt and used camera waypoints instead of trig.
- `std::gpu::Color`: `volec query show std::gpu::Color` gives no match, yet `gpu::Color::rgba(r, g, b, a)` compiles. I found it only by compiling.
- `PassDesc` requires a colour attachment, so a depth-only pass needs a dummy R8Unorm target of the same size, and the pipeline needs a target and a fragment entry. The GPU guide does not mention depth-only passes; I designed the dummy myself (about 10 minutes).
- Shell: `timeout` is not installed on this Mac; a foreground `sleep` is blocked, so I had to wait on a background job.

## 5. The language

What fought me:
- Handle ownership: `Device`, `Queue` and `Mesh` (with Vecs) cannot be passed to a function as let parameters, so `setup(dev, ...)` needed `sink`, and the caller then could not reuse `dev` without `.clone()`. I made the scene struct the owner. The rule is right, but I learned it from the error, not the guide.
- Borrowing an `inout Scene` into closures: I copied the pipeline and bind-group handles into locals before each closure. It works, but I found the pattern by trial.
- `Vec<T>` as a let parameter, `inout` with `&x` at the call: clear once learned.
- Floats: f32 versus f64 literals and `as` casts everywhere. Clear, a bit noisy.
- No trig, no f32 sqrt by name (see section 4).

What I liked:
- Contract messages on GPU calls (usage, align, layout, range) name the fix. I did not hit one at run time.
- WGSL in strings is compiled at build time, so shader errors show a WGSL position. (Untested: none occurred.)
- Headless and window share one code path (the `render` function), which was easy to do.

## 6. Suggestions, ranked by time saved

1. A `PassDesc` for depth-only passes (no colour attachment), or a documented dummy-target pattern in the GPU guide. About 10 minutes lost.
2. Make the query-first hook's allowance clear: say which .vl files it lets through (under 300 lines, whole) and point at `volec query text FILE:A-B` for ranges. Four blocked commands on one file cost four turns.
3. A lint or note for clones inside loops (`x.clone()` in a for body over a large buffer). It caused my two worst timeouts.
4. A std float-math section (sqrt, floor, sin, cos, f32 variants) in the guide, or the planned "std math in vole" work. I avoided trig.
5. f32 literal suffixes in the guide's first page. The fix hook handled it, but the error was the first thing I saw.
6. The `gpa` in tests: say `#[test] fn t(gpa: Gpa)` on the first page of the testing guide.
7. A way to diagnose a windowed program that hangs with no output (a frame-count timeout that prints partial output, or a headless-friendly App).

Numbers: about 8 builds (one backgrounded), 2 `volec test` runs, about 9 headless gpu-runs (two killed after 120 s, both from the clone bug), 3 windowed gpu-runs (all killed, no output). Turns on the clone bug: about 4. Turns on the windowed hang: about 4.
