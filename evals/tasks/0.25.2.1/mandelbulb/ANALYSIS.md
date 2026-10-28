# mandelbulb: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

Works: `volec main.vl -o mandelbulb` builds clean. The Mandelbulb (power 8, and 5 in a close view) and a quaternion Julia set are raymarched in one WGSL fragment shader: sphere-tracing distance estimate, tetrahedron normal, soft shadow, five-sample ambient occlusion, sky and fog. Headless renders three fixed views and prints hit share, brightness, a checksum and GPU timing per view, and writes a PPM of one view (`--view K --shot F`). Windowed mode has a fly camera, mouse orbit, live power ([ ]), Julia toggle, shadow and AO toggles, auto fly.

Verified:
- `volec test main.vl`: 7 tests pass at -O0 and -O2 (after fixing one wrong expectation of mine, header length 1280x720 is 16 bytes).
- `./mandelbulb --headless --size 384 --frames 10 --view k --shot vk.ppm` through gpu-run: hit shares 63.9%, 100.0%, 75.1%; brightness 0.300, 0.166, 0.327. I converted v0 and v2 to PNG and looked: the bulb shows the expected surface detail, the Julia set is a plausible quaternion Julia shape, and the shading is not flat.
- Timing at 1024x1024, view 0, gpu-run, 4 frames a round: 9.32 ms with shadows and AO, 4.90 ms with both off, 8.13 ms at 6 iterations.
- Windowed `--frames 120 --shot win.ppm` through gpu-run (timeout 60): ran, quit by itself, wrote a 2560x1440 frame; I looked at it: lit, detailed Mandelbulb.

Not verified: keys and mouse. The event code compiles, but I did not drive it interactively, so the controls are untested in practice. The windowed frame time (about 100 ms at 2560x1440) is not a measurement: the program printed "no frame in 3 s: the window is occluded or not shown", so the run was partly stalled.

## 2. How you worked

- `volec guide` (full read), `volec guide gpu` (full read), one `guide gpu#...` section (uniform layout), `guide --find` for `assert_eq` and `clamp`.
- `volec query items` / `query show` on std::window, std::window::keys, Event, Mouse, Key, Logical, std::fs, std::num, std::gpu::Surface: about 8 calls. These gave the exact signatures for the window and key APIs; the most useful part of the tooling for me.
- `examples/gpu/fluid2d/main.vl` read directly with cat/sed as the model (window loop, cli, headless, PPM snapshot). Read whole because it was large and I wanted the whole loop.
- Hooks: `volec check` after each write ran automatically; the auto `volec fix` added one missing `&` (queue lent inout). Helpful. The check also reported an `Interp` error pointing at the f-string.
- Did not use `volec edit`, `refactor`, `probe` or `context`. Used Write and Edit, and one sed that failed (below).
- Counts: 2 successful builds, 3 test runs (1 failure from my own arithmetic), about 6 headless gpu-runs, 1 windowed gpu-run, several `volec check` rounds from the hook.

## 3. What went well

- The window, cli, PPM and GPU setup came from the reference example and kept their shape.
- `dev.shader_wgsl` with a plain string constant: the shader compiled and ran first time once the view framing was fixed.
- `volec check` messages were specific and fixable, e.g. "no method 'len' on type 'Interp<closure...>'" pointed at the f-string and said to use `format_in(f"...", gpa)`.
- The borrow auto-fix worked without my having to look up the rule.

## 4. What went badly

- My mistake, not vole's: `sed -i 's/.../' main.vl` (GNU form) on macOS. Error: `sed: 1: "main.vl\n": invalid command code m`. Switched to Edit.
- I used `std::fmt::format_in` and `std::heap_gpa()` from memory. The check said `no 'heap_gpa' in module 'std'`. `format_in` is in the prelude; I should have checked the prelude list in `volec guide` first. Cost one round.
- `f"P6\n{w} {h}\n255\n".len()` fails: "an f-string is a value that prints, with no methods: format it, 'format_in(f"...", gpa)', a Buf". Reasonable, but I expected f-strings to behave more like values; I replaced it with arithmetic.
- First headless views had the bulb filling the frame (95 to 100% hit). I first suspected the march; it was my camera distance (bulb radius about 1.2, view covers about ±0.9 at distance 2.8). I had to work out the frustum by hand. A "frame extent at distance d" helper would have saved time.
- WGSL is not checked at build time: a syntax error only appears at run time as a `gpu::Error::Shader`. I did not test a broken shader, so I cannot judge that message.
- The windowed run was partly stalled by an occluded display; the program's warning was the only signal, and the timing is unusable.

## 5. The language

- What fought me: small things. The f-string value semantics, and the prelude vs std split for `format_in`.
- `inout` and `&` at call sites: `draw(dev, &queue, ...)` once the hook fixed it. The first error ("is lent inout here") was well-formed.
- Struct literals with `pub` fields and methods on `inout self` worked as written.
- Liked: builds about 0.3 s; tests agree at -O0 and -O2; the GPU API reads cleanly. Bind groups `[gpu::bind(0, buf)][..]` are verbose but clear. f64 `sin`, `cos`, `exp`, `atan2`, `clamp` worked without `use`, as the guide says.

## 6. Suggestions, ranked by time saved

1. Check WGSL at `volec check` time (shaders are string constants; errors appear only at run time). Largest potential saving: each shader typo costs a gpu-run.
2. Make `format_in` discoverable from the prelude list or a `std::fmt` doc line (I guessed the wrong path first).
3. A one-line fix hint for `.len()` on an f-string (it has one, but the text is long).
4. A std helper or doc note for "how big does an object look at distance d".
5. A headless timing mode for a window-sized frame without a window, so timing does not depend on display state.

Tool-feedback: I did not record anything with tools/agent-feedback; the points above are the ones to record.
