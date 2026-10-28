# ANALYSIS: deferred (vole 0.25.2.1, std::gpu + std::window)

## 1. Result

Works. `volec main.vl -o deferred` builds clean from my folder, with no C,
no build script and no `unsafe`. The program does what the task asked:

- Scene generated in code: a 12 x 12 checkered floor, 10 cubes, 8 UV
  spheres (`scene.vl`), 512 orbiting coloured point lights.
- G-buffer pass into three colour targets (albedo rgba8, view-space normal
  rgba8, linear depth r32float) plus a Depth32Float hardware depth test, in
  one render pass with three `with_color` attachments and `with_depth`.
- Light culling in a compute pass: one 64-thread workgroup per 16 x 16 tile,
  each light's conservative screen circle tested against the tile, a slot
  taken with `atomicAdd` (cap 256 per tile).
- Lighting compute pass: each pixel shades with its tile's lights, a sun,
  ambient and Blinn-Phong specular, writing an rgba32float HDR storage texture.
- Tone map (ACES, gamma) in a render pass, which also shows the G-buffer
  views: keys 1-4 pick a view, `v` cycles, space pauses, q quits.
- Headless: `--headless` prints the frame time and tile stats; `--shot F.ppm`
  writes the final frame and the three G-buffer views.

Verified and how:
- `volec test main.vl`: 5 passed, -O0 and -O2 agree (RNG range, mesh counts,
  look-at projection, lights in front of the camera, colour range).
- Headless through gpu-run: 0.913 ms a frame at 1280 x 720, 512 lights (120
  frames after 10 warm-up; the output is in `headless.txt`). 158 is the most
  lights offered to one tile, 0 tiles over the cap of 256.
- Read back and looked at: `shot.png` (the lit scene: coloured falloff on
  the floor and the objects), `shot-albedo.png`, `shot-normal.png` (floor
  green = up in view space, flat cube faces), `shot-depth.png` (near white,
  dark at distance).
- Windowed: 120 frames through gpu-run, then it quit by itself (`windowed.txt`).

Not verified, and so not claimed:
- Key handling was not exercised with real key events, so the view switching
  is untested beyond the code reading.
- The culling was not compared with a brute-force reference; the picture
  looks right and the tile counts are plausible, that is all.
- The windowed frame time is not a result: the display was asleep or the
  window occluded, so the frames came from the 10 a second timer
  (`window: no frame in 3 s ... frames come 10 a second`). The 102 ms it
  printed is the timer's.
- The 0.913 ms is a throughput number: frames submitted back to back, one
  wait at the end. Not a latency number.
- The window size is fixed at start; resizing is not handled.

## 2. How you worked

Commands and their rough counts (this session):
- `volec guide` (once, the full core), `volec guide gpu` (once, read to the
  end), `volec guide window` (once), `volec guide testing` (once, for
  `assert` and `assert_eq`).
- `volec query show` about 6 times (std::gpu::with_depth, RenderDesc::depth,
  Compare, VertexLayout::new, Queue::write_buffer, PassDesc::color, f32s,
  bytes_of_f32, copy_buffer), `volec query items` 3 times, `volec query show
  FILE` 1 time (fluid2d's `sim.vl` item list). I did not use `query context`,
  `refs`, `edit`, `refactor`, `probe` or `reduce`: I was writing new code, not
  changing or debugging existing code.
- `volec check` roughly 10 times (mostly via the check hook, which runs after
  each Write/Edit); `volec main.vl -o deferred` 5 times; `volec test` 3 times.
- `volec fix` was applied by the hook 1 time and fixed 5 errors: the `&`
  markers on `inout` arguments and the `&mut` Rust spelling. Good.
- The `query-first` hook blocked one `grep` of `compiler/std/gpu/mod.vl`: the
  hook was right (the rule says use query for std source), and the `query show`
  it suggested gave the same answer in one call. Cost: one turn.
- gpu-run: 4 headless runs and 1 windowed run. Two waited (157.7 s and 83.7 s
  for others' GPU programs); the rest 0 to 1 s.
- `tools/agent-feedback`: 3 lines recorded.
- Ignored: `query context` (I did not need an existing item), `refs`, `edit
  patch` (new code, not patches), the `ArtifactX` and Docs tools (not relevant).

What helped: the compiler's first error line plus its `try:` line. Most
fixes were mechanical and I applied them in one pass. The `volec fix` hook
took the `&` markers without a turn from me.

What did not: the shader errors. A WGSL problem (a storage format) is only
reported when the program runs, through `gpu::Error::Shader`, not by
`volec check`. That cost one GPU lock wait (the 157.7 s one) to learn it.

## 3. What went well

- The checker's messages are specific: `expected '[f32; 3]', got '[f64; 3]'
  ... 'col' is '[f64; 3]' from its literals at scene.vl:110:17 ... annotate
  it, 'col: [f32; 3]'`. The `try:` line for an annotation was right every time.
- The ownership errors told me the exact fix: `own.move_out: cannot move 'dev'
  (Device) out of a reference ... take the parameter 'sink' to own it and
  store it`. I applied `sink` and it compiled.
- `shader_wgsl` with a `[u8]` concatenation helper (`source([FRAME, GBUF][..])`)
  made per-pass WGSL modules clean: each module declares only its bindings,
  and the bind-group layout is derived from what the entry points use. This
  matched the guide.
- The render pass API (`PassDesc::color(a).with_color(b).with_color(c)
  .with_depth(d)`) and the pipeline's `RenderDesc::target` /
  `depth` made the G-buffer a single short block of code.
- `gpu::u32s` and `map_read` plus `copy_buffer` gave the tile statistics with
  about 15 lines.
- The window's `set_title` and `Event::Key` worked as the guide said.
- The compile was fast: about 0.4 s to 0.9 s for `volec main.vl -o deferred`.

## 4. What went badly

Every error, with a count of how many attempts it cost.

1. `volec check`: `scene.vl:111:87: error[type error] expected '[f32; 3]',
   got '[f64; 3]'` and `scene.vl:121:33: error[type error] expected 'f32', got
   'f64'`. Float literals default to f64, so `let g = if c { 0.52 } else { 0.36 }`
   and `let s = if side == 0 { -1.0 } else { 1.0 }` were f64 and failed when
   passed to f32 parameters. Fix: `let g: f32 = ...`. Four annotations; the
   message was clear, but the default is a trap for a GPU program that is
   mostly f32. Suggest: infer float literal type from the first use, or a
   `1.0f32` suffix in the guide's first table.
2. `cannot derive Debug for 'Orbit': field 'color' of type '[f32; 3]' has no
   Debug`: I had derived `Eq, Debug, Clone` on a struct with floats. `Eq` on
   floats is also wrong, and the checker did not say so. Fix: removed the
   derive. A note in the guide on deriving with floats would have saved a turn.
3. `unknown module 'shaders'` when checking `render.vl` alone: expected, since
   the module tree is in `main.vl`. Not a problem once known; the guide says
   "`mod x;` loads x.vl" but not that a file checked alone cannot resolve its
   siblings. Cost: one turn of confusion.
4. `constant 'VIEWS' has type '[[u8]]'; constants must be integers, floats,
   bool or string literals`. I wanted a const array of string names. The fix
   the checker gives is a `static` array with an explicit size; I replaced it
   with a function (`fn view_name(mode: i64) -> [u8]`), which is simpler.
5. `'COMP' is private` for the shader consts used from another module. Fixed
   with `pub const`. The `volec fix --suggested` offered exactly that.
6. `own.move_out: cannot move 'dev' (Device) out of a reference` (and for
   `queue`, and `self.tv`). Fixed with `sink` on the parameters and by
   replacing the stored `TextureView` with `self.target.view()`. The second one
   I did not expect: a `let` self cannot return a field by value, and the
   checker reported it at the `return` line. Two turns.
7. `conv.rust: '&mut enc' is Rust's spelling` three times, plus `conv.marker:
   'enc' is lent inout here`. The hook's `volec fix` changed them. Fine, but I
   wrote `&mut` from habit; 3 edits the hook made for me.
8. `no method 'to_vec' on type '[u8]'`: the message gave the fix (push into a
   Buf); I copied a path with `Buf::push_str` instead. One turn.
9. The WGSL storage-texture format: an error at run time:
   `deferred: gpu: the shader did not compile: 17:51: error wgsl.unsupported:
   storage textures in this release are rgba8unorm, rgba32float, r32float,
   r32uint, r32sint or rgba32uint`. The message is good, and it names the
   formats, but:
   - it came from the run, through the GPU lock (waited 157.7 s), not from
     `volec check`: the shader text is a string, and nothing checks it at
     compile time;
   - the guide's format list (`Format::` in "Usages and formats") does not say
     which formats are storable, so I chose `rgba16float` from the guide's
     own list and was wrong. Repro: `dev.texture(w, h, Format::Rgba16Float,
     usage: TextureUsage::STORAGE_BINDING | TextureUsage::TEXTURE_BINDING)`
     then `texture_storage_2d<rgba16float, write>` in a compute module.
     `dev.texture` accepted it, and std's own `Format::is_storable` returns
     true for `Rgba16Float` (compiler/std/gpu/types.vl:96-107). So std says
     storable and the WGSL translator of this release refuses it: the two
     lists disagree, and the disagreement shows only when the program runs.
10. The BSD `sed -i` took my pattern as its suffix (`sed: 1: "shaders.vl ...":
    unterminated substitute pattern`). My mistake (macOS wants `sed -i ''`),
    one turn.
11. Frame timing when the window is hidden: 100 ms frames, from the 10 a second
    timer. The guide says so (`window: no frame in 3 s`), and I reported it,
    but a headless-friendly way to time the windowed path would help: e.g. a
    `--frames` mode that does not wait for the display.
12. The window needs a display for `--frames` timing. The brief forbids long
    windowed runs, so the frame time claim is headless only.

Time sinks: the float-literal and derive errors (about 4 turns); the
`own.move_out` errors (2 turns and a redesign of `target_view`); the storage
format (one GPU lock wait, about 2.5 minutes, plus a rebuild).

## 5. The language

What fought me:
- f32 vs f64 defaults for literals, everywhere a GPU program passes floats.
  The check was strict, which is good, but the default makes everyday code
  noisy.
- Ownership of handles: `Device`, `Queue`, `TextureView` are owned values, so
  any struct that stores one needs `sink` in its constructor, and any method
  that returns one from a `let self` needs a copy or a re-creation. The rule
  is clear once the error says it; before that it cost two turns.
- No `static` arrays of strings of the simple kind: `const X: [[u8]]` is not
  allowed, and the right form is a function or a `static` with an explicit
  size.
- The `inout` marker and `&x` at the call site: clear, and the hook fixes the
  common mistake. Three `&mut` habits in one file.
- The guide's shader strings with `\n\` continuation: workable for 100-line
  WGSL, but the lines are noisy and nothing checks the WGSL until run time.
  Checking WGSL at compile time would close this gap.

What I liked:
- Views and `sink`/`inout` gave a clear picture of what each function owns:
  the lights' `pack_lights(lights: [Orbit], ..., out: inout Vec<f32>)` reads
  like its contract.
- `#[test]` next to the code, `assert` and `assert_eq`, and `volec test`
  running both -O0 and -O2: a test failure printed its line and value at once
  (`scene.vl:342:5: assertion failed: 'w == 1.0': w = 14527349e-6`).
- Integer wrap in the RNG (`self.s * 6364136223846793005 + ...`) worked as the
  guide says, with no overflow error.
- The `Result<_, gpu::Error>` plus `?` through the GPU setup kept `run` short.

## 6. Suggestions, ranked by time saved

1. Check WGSL at compile time, and make `Format::is_storable` agree with the
   WGSL translator (it lists Rgba16Float, which the translator refuses). This
   cost a GPU lock wait and a rebuild (about 5 min each time).
2. Float literals: infer the width from the first use, or document that
   `0.5` is f64 in the first table of the guide, with the `f32` form beside it.
   Four annotations in one file. (Several turns.)
3. `volec check` on a file that is a module (e.g. `render.vl`) should say it
   is a module of `main.vl`, instead of `unknown module 'shaders'`.
4. A `--frames` windowed mode that times the GPU without waiting for the
   display (e.g. the same frame loop with no `win.request_frame`), or a
   guide note that the windowed timing needs a display.
5. Derive rules: `#[derive(Eq)]` on floats is accepted silently by the
   checker's derive pass and wrong; `Debug` on `[f32; 3]` fails with a clear
   message. Say in the guide what derives work on which field types.
6. A `static` for const arrays of byte strings in the first guide table
   (`const VIEWS: [[u8]]` is refused; the fix is a function).

Repro for 9 (storage format), in `main.vl`'s shader module:
`@group(0) @binding(7) var hdr: texture_storage_2d<rgba16float, write>;` on a
`dev.texture(w, h, Format::Rgba16Float, usage: STORAGE_BINDING | TEXTURE_BINDING)`.
Run it through gpu-run: `deferred: gpu: the shader did not compile: 17:51:
error wgsl.unsupported: storage textures in this release are rgba8unorm,
rgba32float, r32float, r32uint, r32sint or rgba32uint`.

Files: `/Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/deferred/`:
`main.vl`, `render.vl`, `scene.vl`, `shaders.vl`, `README.md`, `ANALYSIS.md`,
`headless.txt`, `windowed.txt`, `shot.png`, `shot-albedo.png`,
`shot-normal.png`, `shot-depth.png` (and the PPMs).
