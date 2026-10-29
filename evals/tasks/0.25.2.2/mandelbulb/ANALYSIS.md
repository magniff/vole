# mandelbulb: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

Works: a Mandelbulb and a Mandelbox raymarched in one std::gpu fragment pass per frame (WGSL in shader.vl), with distance estimation, sphere tracing, soft shadows, ambient occlusion, an orbit-trap colour, a smooth easing camera and a live power parameter (arrow keys). `volec main.vl -o mandelbulb` builds with no errors. The headless mode renders four fixed views and prints timings and checks.

Verified:
- `volec test main.vl`: 4 passed (-O0 and -O2 agree).
- `./mandelbulb --headless --frames 20` through gpu-run, exit 0; output in shots/headless_640x360.txt: view 0 1.63 ms a frame, view 1 2.69 ms, view 2 1.91 ms, view 3 (Mandelbox) 2.55 ms at 640 x 360 (20 frames after one warm-up).
- Pictures read as PNG (shots/view0..3.png, shots/power12.png). The Mandelbulb, close-up and Mandelbox are recognisable; power 12 differs in structure from power 8.
- Windowed: `./mandelbulb --frames 120` and `--frames 60` each quit by themselves with exit 0, through gpu-run.

Not verified:
- The window was not visible (run from a background shell): the reported frame time is the 10 fps occluded timer (about 100 ms), not a measurement.
- Keys and mouse were not exercised by hand. The code paths compile; nothing pressed a key.
- Timings are wall-clock (submit to wait_idle), not GPU timestamps.
- Earlier, the same views measured 15 to 20 ms at 640 x 360 while machine load was high (15-minute load near 10); later repeats were 1.6 to 3.3 ms. I did not establish a cause beyond load and did not use the earlier figures.

## 2. How you worked

- `volec guide` (core), `guide gpu` (read in two parts), `guide gpu-render` (skimmed), `guide math`, `guide testing`, `guide window`: about 6 reads.
- Read examples/gpu/fluid2d (main.vl, sim.vl): the most useful source. I copied the shape (WGSL const strings, a Sim/Tracer struct, snapshot, Event::Key, Mouse), not the code.
- `volec query items std::gpu`, `query show std::window::keys::Named`, `query show std::gpu::TextureUsage`, `query items std::cli`: about 6 queries, each answered in one call.
- Not used: `query context`, `edit patch/replace`, `refactor`, `fix --suggested`. Edits were plain file writes or Python/sed string replacement (the WGSL-in-string edits especially).
- Builds: 9 `volec main.vl -o` runs; one round with 2 type errors, then clean. `volec fmt` once, `volec test` 4 times.
- The hook ran `volec fix` mechanically after my Write of main.vl (let mut, *look, x to &x); those were correct. The hook's type-error help was useful. Friction: files changed on disk under me, so later Edit or Read needed a re-read (four notices).
- Headless runs through tools/gpu-run: about 14, each seconds long.

## 3. What went well

- The GPU side was quick once I had fluid2d as a shape: Tracer (device, queue, uniform buffer, pipeline, bind group), `draw(self, enc: inout, target)` with a closure capturing self, and snapshot/bench written against it.
- `pub const SHADER: [u8]` in its own module, then `dev.shader_wgsl(shader::SHADER)?`: clean.
- The CPU-side camera (camera.vl) is plain vole: structs, inout self methods, #[test]s that run at -O0 and -O2.
- The f-string-as-[u8] error gave the exact fix (`format_in(f"...", gpa).as_slice()`), used verbatim.
- `dev.texture(w, h, fmt, usage: ...)` with a named argument read well; TEXTURE_BINDING and RENDER_ATTACHMENT were findable via query show.
- The loop (volec main.vl -o, one gpu-run headless render, PNG view) is seconds per iteration and found the real bug (section 4).

## 4. What went badly

Errors that confused me:
- `error[type error] unknown type 'Matches'` with `help: add use std::string::Matches;`. The type is std::cli::Matches<A>. The suggested module is wrong; I found the right one with `query items std::cli`.
- `error[type error] an f-string is a 'std::Interp' ... not '[u8]'`: the help was right (format_in), but the caret points at the f-string, not at the argument that needs [u8].

Time sinks:
- The dark picture: about 4 build-render-look rounds. The Mandelbulb's distance estimate is small across the surface, so the soft shadow `res = min(res, 10*h/t)` darkened nearly everything, and occlusion (`2.5 * occ`) did too. Toggling --no-shadows and --no-ao (one run each) located it. The fix was constants: shadow k 10 to 4, start t 0.01 to 0.02, step clamp 0.005 to 0.01, AO 2.5 to 1.5 with a 0.35 floor. No tool told me a DE like this needs a smaller shadow k; I found it by looking at PNGs. A way to render a single shader term would have saved two rounds.
- Timing: first numbers (15 to 20 ms) and later ones (1.6 ms) differ 10x for the same code. gpu-run serialises only gpu-run users; other load inflates timings. I spent two runs on attribution before deciding it was load. The load line printed by gpu-run does not show non-gpu-run GPU jobs.
- The window could not be checked: from a background shell it is not shown, so frame times and key handling are unmeasured. This is the largest gap.
- My own mistakes: the first headless --shot without --view overwrote one file for all four views (fixed: --shot now needs --view); I ran a duplicate timing command; I deleted the view PNGs in a cleanup and regenerated them.

Guide and docs gaps (as far as I could find):
- No guide example shows a raymarcher or a full-screen fragment pass in WGSL; gpu-render shows a fullscreen triangle in MSL. I wrote the WGSL from guide gpu's DRAW example, which worked.
- The render-to-texture then blit (sampler plus bind_texture and bind_sampler) worked as the textured-quad example in the guide.
- No documented guidance on WGSL pow/acos/atan2 behaviour in the Mandelbulb's domain. I guarded them (clamp, max(r, 1e-9)) out of habit, not because the language required it.

Language friction:
- WGSL inside vole strings is verbose: every line ends with `\n\`, and from Python each backslash must be doubled. A multi-line raw string or the planned wgsl{} block (0.27) would remove most of that, and it was the bulk of the typing.

## 5. The language

What fought me:
- The inout and &x rule: `press(&inp, look, &cam, ...)` where `look` is itself an inout parameter. The hook fixed two of these; I reasoned out the rest. Consistent once learned.
- Tracer is passed by self to draw and by let to screen_of, then reused. It compiled, but the signature does not say whether the value is copied or borrowed; the guide does not say either.
- Defaulted generic types (Matches<A = Gpa>) appear in errors but are invisible in calls; fine in practice.

What I liked:
- match on Logical::Named(Named::ArrowUp) and Logical::Char(c) reads well.
- Float and integer methods (clamp, max, sqrt, atan2, acos, sin, cos, powi) worked without `use`, as the math guide says.
- Structs with pub fields and impl with inout self read like Rust with a clearer mutability story.

## 6. Suggestions (ranked by time saved)

1. A way to render or inspect one shader term (a debug output mode) without a rebuild and a PNG round. The dark-image loop took about four rounds.
2. A headless window or screenshot path for std::window (or an offscreen surface running the same event loop), so key handling and frame timing can be checked without a visible window. This is the gap I could not close.
3. GPU timestamps (or a timed pass) so frame times are not wall-clock through wait_idle, and load from other GPU users can be told apart from the program's own cost.
4. Fix the unknown-type help: name std::cli::Matches (it suggested std::string::Matches).
5. A multi-line raw string (or the planned wgsl{} block) for shaders.
6. Point the f-string error's caret at the argument that needs [u8].
7. Document whether a struct passed to a self method is copied or borrowed (Device, Queue and BindGroup behave as handles here).

Numbers: about 9 builds (1 round with 2 type errors), 1 volec fmt, 4 volec test runs, about 14 headless and window runs through gpu-run, about 12 query and guide reads. Four shader iterations for lighting, each a build plus a headless render.

Feedback lines recorded with tools/agent-feedback: the Matches help naming the wrong module; the timing variance under load; the window not shown from a background shell.

Known limits (also in README.md): the Mandelbulb estimate is not a strict bound, so grazing angles show some speckle; the Mandelbox bounding radius (5) is a guess that fits the views; window frame time and keys were not measured on a visible window.
