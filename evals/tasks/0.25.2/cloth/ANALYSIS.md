# cloth: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the Write tool refused the agent's own write of this file ("Subagents should return findings as text"). Nothing is edited but this note and the headings' markup; the message's file list is kept at the top.

Files (all in /Users/magniff/workspace/tachyon/evals/tasks/0.25.2/cloth/): main.vl (CLI, headless checks, window loop), sim.vl (GPU side), shaders.vl (WGSL), geom.vl (CPU maths, camera, checks, 6 #[test]s), README.md, headless-run.txt, headless-wind.txt, shot.png, wind.png, win.png (window shot, converted, not inspected closely). Binary: cloth, built with `volec main.vl -o cloth`.

## 1. Result

- Build clean; `volec test main.vl`: 6 passed at -O0 and -O2.
- Window: `./cloth --frames 120` runs to completion, 8.28 ms a frame at 1280x800 with physics on (via gpu-run).
- Headless default (`./cloth --headless --frames 600`): constraint error after one frame falls 0.0111 (2 iters) -> 0.0048 (16) -> 0.0035 (32), mean 1e-5; no NaN; energy does not rise after 1 s; steady worst stretch 0.27 (mean 0.7%) at the pinned corner; drag moved the middle particle to its target exactly (0.00000 away).
- Headless --wind: no NaN; worst stretch settles near 0.30 at the pinned corner, so my own 0.3 threshold FAILS there. Reported as a fail, not moved.
- Not verified: real mouse, keyboard and arrow-key orbit (pick and drag-plane are covered by the unit test and the headless drag, which use the same functions). Window only run 120 frames. The solver is soft (Jacobi with averaging).
- Gpu-run waits: 0.0 to 4.4 s, load 2.0 to 2.6. Contention did not block me.

## 2. How I worked (approx.)

- volec guide (main, gpu, window): about 3 calls, useful.
- volec query items/show/context: about 15, useful for std signatures.
- volec check / build: about 15; the post-Edit check hook was the most useful loop.
- volec test: 4 runs. gpu-run: 9 headless, 1 windowed.
- Edits via the Edit tool; I did not use volec edit patch or refactor, because hooks blocked my shell/python rewrites of .vl.
- query-first hook blocked about 8 reads (cat/head/grep of .vl, even 272-line files). A plain Read would have been faster.
- A python rewrite of .vl was blocked, and it silently did not run, leaving a doubled `pub pub` I had to fix.
- volec fix --suggested (run by the hook) rewrote a correct cast chain in geom.vl into a no-op double cast; I reverted it by hand. The "changed on disk" note gives no diff.

## 3. What went well

- GPU API from fluid2d's example: shader_wgsl, bind_group, encoder, compute_pass closures capturing self, render passes with depth. Worked first try once the bug below was avoided.
- WGSL front end accepted everything (select, clamp, pow, normalize, cross, sin/cos, mat4x4 uniform, positional struct constructors, for-loops). No WGSL-side errors.
- Runtime contract messages with file and column (gpu.usage on copy_buffer).

## 4. What went badly

- BUG (biggest time sink, about 40 min): `dev.compute_pipeline(dev.shader_wgsl(SRC)?, "integrate")?` fails with "gpu: the pipeline was rejected: no compute entry point 'integrate' in the shader", though the entry exists. Binding the shader to a let first works. Same for RenderDesc::new(dev.shader_wgsl(SRC)?, ...). Minimal repro is 6 lines (a shader temporary loses its entry table before the pipeline reads it). Logged with tools/agent-feedback. The message sent me to the WGSL first.
- My scene bug (about 5 runs): sphere overlapped the sheet's start plane, so collision snapped it out in one step (1.7 strain). Found by bisecting iterations and printing positions. Moved the sphere to (0, 0.9, 0.5).
- `Gpa` is sealed: `#[test] fn` cannot construct one. The help text ("pass gpa down") is not followable in a test. Logged.
- No sqrt, sin, cos, or std::math in 0.25.2: sqrt is C libm via unsafe. I wrote Newton's method and turned the camera by constant steps. Logged.
- `copy_buffer` gpu.usage message does not say which buffer lacks COPY_SRC.
- `no variant 'Left' in enum 'Named'` (the variant is ArrowLeft), no suggestion.
- Doubled `pub pub` from a blocked-then-partly-applied edit: parser error "expected an item, got 'pub'".

## 5. The language

- Fought me: GPU handle temporaries (section 4); no if-let, no operator overloading (I used add/sub/scale/dot), no trig or sqrt, no Gpa in tests; cast precedence care with `as`.
- Liked: named imports only; errors with file/line/column and help lines; defaults in Arg::option; vertex-index-only cloth drawing needs no vertex buffer.

## 6. Suggestions, ranked by time saved

1. Fix the temporary-shader bug (or say "bind the shader to a let first" in the error). Biggest time sink.
2. Add std::math (sqrt, sin, cos, tan, abs, min, max, floor for f32/f64).
3. Let #[test] fns get a Gpa, or explain how to test an allocating fn.
4. volec fix --suggested: show its diff, or do not rewrite code that already type-checks.
5. Suggest enum variants on a wrong name (did you mean ArrowLeft?).
6. Name the buffer in gpu.usage for copy_buffer.
7. Docs: note that Jacobi-with-averaging is soft, and that ping-pong needs an even count to end in the first buffer.

## 7. Commands

Commands used: `volec main.vl -o cloth`; `volec test main.vl`; `gpu-run --timeout 200 -- ./cloth --headless --frames 600` (and --wind); `gpu-run --timeout 120 -- ./cloth --frames 120`. Feedback recorded via tools/agent-feedback: 3 entries (shader temporary, std math, Gpa in tests).
