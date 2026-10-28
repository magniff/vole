# ANALYSIS: mandelbulb

## 1. Result

Works: a Mandelbulb and a Mandelbox raymarched in one WGSL fragment shader,
with distance estimation, sphere tracing, normals, soft shadows, ambient
occlusion, fog and an orbit-trap palette. The window has a fly-through
camera (on at start, P toggles it), WASD/QE/arrows/shift flight, left-drag
look, a live power knob (`[` `]`), a fractal switch (M), and toggles for
shadows (L) and AO (O). The headless mode renders fixed views to PPM and
prints timings and brightness statistics.

Verified:
- `volec test main.vl`: `test main.vl: 9 passed (9 #[test]; -O0 and -O2 agree)`.
- `./mandelbulb --headless --check` through gpu-run: three views per fractal,
  each "neither black nor flat" (mean luma 0.16 to 0.29, spread 0.06 to 0.16),
  and "repeatable: two renders of view 0 are identical". Also with `--power 3.5`.
- Read the rendered PNGs (converted with ppm2png.py): the Mandelbulb reads
  as a Mandelbulb; the Mandelbox view is a close-up of the fold structure.
- `./mandelbulb --frames 120` through gpu-run, timeout 60: quit by itself,
  `2560 x 1440 pixels: 120 frames, 13.55 ms a frame (73.8 fps)`, waited 0.0 s,
  load 4.5.
- Timings (gpu-run, uncontended): Mandelbulb 320x180 about 1.0 to 1.2 ms a
  frame; 640x360 about 2.4 to 2.5 ms (view 0), 4.3 ms (view 1, close); Mandelbox
  640x360 about 6.5 to 9 ms.

Not verified: the mouse and keys in a live window. They are checked only by
the CPU tests (drag, held keys, P), not by a person or a scripted event
stream. The windowed run used the fly-through only. I did not look at the
fly-through over a long time, and there is no Julia set (the Mandelbox is the
second fractal).

## 2. How you worked

Commands and rough counts (this session):
- `volec guide` (full, about 2k tokens), `volec guide gpu`, `volec guide window`:
  read once each. The gpu and window guides were enough to write the
  program; I did not use `--find` or `TOPIC#SECTION`.
- `volec query`: about 12 calls, `items`, `show`, `context`, `text`. `query text
  FILE:A-B` replaced reads of the fluid2d example once the hook refused `sed`
  and `grep` on .vl files (3 blocked shell commands).
- `volec check main.vl`: run by hand about 7 times, and the check hook ran after
  every Edit. The hook was useful: its auto-fixes made `&s` for inout arguments
  and made a private const public, and each message gave the exact fix.
- `volec fix --only unused main.vl`: removed two unused imports in one call.
- `volec main.vl -o mandelbulb`: 2 successful builds, 0 failed builds (the
  errors were all caught by `check` first).
- `volec test main.vl`: 2 runs.
- I edited .vl files with the Edit tool, not `volec edit patch`. The hook did not
  block it. I did not try `volec edit patch` or the refactor commands; the
  edits were small and I was already working in the text.
- `tools/agent-feedback`: 5 entries (listed in section 4).
- `gpu-run`: 11 runs, all with waited 0.0 s (load 3.8 to 5.2).

Turns: about 60 tool calls in total. The biggest time sinks were the three
std gaps (no math, no `include_str`, no `parse_i64`), each one turn to find
and one to work around, and the shader embedding (about 4 turns).

## 3. What went well

- The error messages were specific and nearly always came with the fix. The
  `own.move_out` message ("take the parameter 'sink' to own it") and the
  `conv.marker` one ("mark it '&s'") fixed the code in one edit each. The
  `expected 'i32', got 'i64'` message told me exactly which literal to annotate.
- `volec check` is fast (under a second), and the hook kept it in the loop,
  so I never ran a build that failed.
- The WGSL subset took everything I wrote the first time: `for` with `break`,
  `if`/`else if`, `pow`, `acos`, `atan2`, `select`-style branching, vec
  swizzles like `k.xyy`, `vec3<f32>(t)` splats, and a `@builtin(position)`
  struct. The shader compiled and rendered correctly on the first run after
  the embedding. No translator bugs.
- The fluid2d example was a good model: its window loop, `Event` matching,
  headless PPM snapshot and `monotonic_now` timing carried over almost line
  for line.
- `volec test` runs -O0 and -O2 and checks they agree. It caught nothing here,
  but it is a good default.
- `gpu-run` printed the wait and the load, which made it easy to report.

## 4. What went badly

Errors and gaps, quoted:
- `error[type error] undefined variable 'include_str'` followed by
  "std's names: `volec guide std`". `docs/design/gpu.md` (section 2.10, "Where it
  runs") names `include_str("cells.wgsl")`, but no example uses it and the
  guide does not mention it. I had to paste the WGSL into a `const` string
  line by line (generated once with a short python script, then edited by
  hand). That is a workaround I would not want to repeat.
- `error[type error] no 'parse_i64' in module 'std::num'` with `help: did you
  mean 'parse_f64'?`. The suggestion is wrong for my need. The prelude
  `parse_int` is the right function, and the guide does mention `parse_int`,
  but I had guessed the `std::num` name first.
- No math module. `volec query items std` lists no `math`, and `f64` has no
  methods ("no methods on numbers" in the core guide). I wrote `sin64`, `cos64`
  (through `sin64`), and `sqrt64` (Newton) in scene.vl. That is 30 lines of
  glue, and the tests check them. The queued std math work (0.25.3, per the
  project plan) would have removed it.
- `error[type error] constant 'MARCH' has type '[u8]'; constants must be
  integers, floats, bool or string literals` with the hint to use `static`. I
  then embedded the shader as a `const` string literal instead, because the
  `static` route would not take `include_str` either. The two hints together
  were confusing: the first said "use static", the next fix was not static.
- `error[type error] expected '[u8]', got '[i64; 12]'`: an array literal is not a
  slice, and the literal defaults to `i64`, so `let px: [u8] = [1, 2, ...]`
  fails twice. The fix that worked is `let px: [u8; 12] = [...]` and then `px[..]`.
  The suggestion `[...][..]` would still have typed the elements as `i64`.
- `error[type error] 'Gpa' is sealed: only module 'std' makes one` in a
  `#[test]`. There is no way to get an allocator in a test, so anything that
  takes a `Gpa` (my PPM header writer) is untested. I dropped that test and
  tested the statistics instead. This is a real gap: a test cannot exercise
  allocating code.
- `error[type error] expected 'i32', got 'i64'` for `var code = 0;` returned
  from a function declared `-> i32`. The hint is good and the fix is one word,
  but an untyped `0` that is later returned as `i32` could infer.
- `own.move_out: cannot move 'dev' (Device) out of a reference`: a constructor
  storing its parameters in a struct. Needed `sink`. Clear message, but the
  rule ("a let parameter is read-only") is easy to forget in a constructor.
- `error[conv.marker] 's' is lent inout here` (x3): passing an inout parameter
  on to another inout function needs `&s`. The hook fixed these itself; it
  was fine.
- `warning[use.unused] unused import 'Keys'`: my mistake; `volec fix --only
  unused` fixed it.
- Float asserts: I wrote a `near` helper for tolerance comparisons rather than
  look for a tolerance assert in std. Not a bug; a note on the test API.
- The hook blocked a compound shell command because one part of it read a
  .vl file with `head`. The other parts did not run, and the message said
  only "blocked". I lost one edit that way (a python rewrite of scene.vl) and
  had to check the file to see that it had not run. The refusal names the
  blocked part, but the whole command is dropped.
- Edits raced with the hook: "File has been modified since read" twice, after
  the hook's own auto-fix had changed the file. Re-reading fixed it.
- Time sinks by count: `include_str` (3 attempts: check, then the hook's fix
  message, then the embedding), the `[u8]` array literal (2), `parse_i64` (1
  plus a re-read), the `static` constant (2).

Performance and a visual issue, not a tool bug: the first Mandelbox render
was washed out, because fog (`exp(-0.02 t^2)`) was tuned for the Mandelbulb's
scale and the Mandelbox sits at distance 9. I changed the fog, the palette and
the ambient term, and added a per-fractal step (0.6 for the Mandelbox): that
fixed the look and the grainy far field.

## 5. The language

What fought me:
- Ownership at the edges: a constructor (`Renderer::new`) that stores a
  `Device` and a `Queue` must take them `sink`. Reading the code, a `let`
  parameter looks like it can be stored; the error is accurate, but the rule
  is not what Rust programmers expect from a constructor.
- Literals: `[u8]` and `[i64]` do not coerce from array literals; the
  integer default is `i64` even where `u8` is meant.
- No methods on numbers and no `f64` math: every `sqrt` is a call in a module
  you write yourself.
- `const` only takes literals, so a shader in another file needs `static`, a
  `const` string, or the `include_str` that is not there.
- No allocator in a test.

What I liked:
- `inout` and `&x` at the call were easy once the message said where to put
  `&`. `let` as the default is the right default for uniform data passed
  around a frame.
- Struct literals and the `Opts` struct holding a `[u8]` slice worked as
  written.
- The GPU API matched wgpu closely enough that the fluid2d example was a
  complete guide. The bind group entries, `RenderDesc::new`, `PassDesc::color`
  and `copy_texture_to_buffer` with 256-byte stride all behaved as documented,
  and the contract messages (`gpu.align`, `gpu.usage`) were not triggered.
- `volec test` at -O0 and -O2 in one command.

## 6. Suggestions, ranked by time saved

1. Ship `include_str` (or let `const` take a file's text), or document that
   `include_str` is not available yet. I lost about four turns on the shader.
2. The 0.25.3 std math (sin, cos, sqrt, atan2, pow for f32 and f64) would have
   removed about 30 lines and the tests of them. Even a free function
   `std::math::sqrt(x)` would have done.
3. Let `#[test]` take a `Gpa` (or a test allocator). Without it, allocating code
   cannot be tested.
4. Make array literals take the element type from the slice type they meet
   (`let px: [u8] = [1, 2, 3]` should type the literal as `u8`).
5. In the `static` hint, say when `static` cannot hold the value, or suggest
   `include_str` or a `const` string.
6. Make the query-first hook refuse only the blocked part of a compound command,
   or say which part it refused and that the rest was not run.
7. Constructors: a hint for `own.move_out` that says "store it: take it `sink`
   in the signature" would save a re-read.
8. Infer a return literal's type from the function's return type (`var code = 0;`
   returned as `i32`).
