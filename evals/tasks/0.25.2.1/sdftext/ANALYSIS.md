# sdftext: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

Works:
- Atlas: 41 glyphs (space, 0-9, A-Z, `. - + :`) from a hand-written stroke font (glyphs.vl), turned into signed distance fields on the CPU at startup (atlas.vl): one 512x384 R8 texture, 8x6 cells of 64 texels. Build time 10-25 ms depending on load.
- Rendering (gfx.vl): one render pipeline draws the canvas triangles (draw.vl). Glyph vertices sample the atlas via textureSampleLevel; the edge is antialiased with fwidth. Rotation is per glyph (CPU-side corners); rectangle clipping cuts the atlas UVs proportionally.
- Widgets (ui.vl): buttons (+, -, RESET), slider, text field (typed bytes, Backspace, focus), scrolling list (wheel, click to select, scrollbar). Immediate mode with hot/active/focus ids.
- Page (demo.vl): title, five sample lines at cap heights 14-72, four turned "TURN" lines at 0/10/20/30 degrees, readout, widget column.
- Modes: window (default); `--frames N --shot F.ppm`; `--headless [--shot F.ppm]`.

Verified:
- `volec test main.vl`: 4 tests pass at -O0 and -O2. One failed on my own wrong expectation (0.99 vs the 0.86 the encoding gives on a stroke centre-line); corrected.
- `./sdftext --headless` through gpu-run: exit 0, "all checks pass: 0 failures":
  - 40 of 40 glyphs: stroke midpoint inside, cell corner outside, 0.5-45% of the cell inside.
  - Largest step between neighbouring texels 32 of 255 (a true SDF allows about 46).
  - GPU atlas read back with copy_texture_to_buffer: 196608 texels, 0 differ from the CPU's.
  - Scripted widgets: hover makes + hot; two clicks give count 2; click on - gives 1; drag to 0.8 gives slider 0.800; click in field, type "vole sdf", Backspace gives "vole sd"; 3-line wheel and click select row 11.
  - Crispness: edge band of an I stem is 2 px at glyph sizes 12, 40 and 120.
- Windowed: `--frames 60 --shot` through gpu-run ran 60 frames and wrote 1600x1160 (scale 2). The display was asleep, so frames came from the 10 fps timer. The PNG matches the headless layout.

Not verified:
- Live pointer and keyboard input in the window. I could not drive a real window; the input path feeds the same Input struct the headless script uses, but it was not exercised with real OS events.
- textureSample (only textureSampleLevel is used).

## 2. How you worked

Estimates.
- Reading: `volec guide` (full), `guide gpu`, `guide window`, `guide math`, one `--find fwidth` (no match). About 6 guide calls.
- Discovery: `volec query items std::gpu` and `std::window` (the signatures with `requires` clauses were the most useful), `query show` for Mouse, Key, Event, Text, Named, Logical, Color, Blend, and `query items std::window::keys`. About 12 queries. Read examples/gpu/fluid2d (window loop, headless PPM snapshot, CLI).
- Did not use: `query context`, `edit patch/replace`, `refactor`, `volec fix --suggested` (I applied suggested fixes by hand).
- Build loop: volec check via the hook after each edit; `volec main.vl -o` about 7 times; `volec test` 3 times. The fix hook auto-changed my `&mut x` to `&x` on call sites.
- Roughly 85 tool calls total. Python edits to my own .vl files for multi-spot string and threshold changes; the query-first hook did not block them (not in compiler/src).
- Hooks: check-after-edit gave precise errors with try: lines. The fix hook saved a round. A "changed on disk" notice after a formatter run forced a re-read before the next Edit; noise, but harmless.

## 3. What went well

- `query items` shows each signature with its requires clauses; I could read the preconditions before calling (write_texture, draw, buffer usages).
- Compile errors were specific: `'clamp' is no method on i64 ... try: std::clamp(tx, 0, CELL - 1)` fixed a class of errors at once. The static-vs-const error for float arrays stated the fix.
- The GPU lifecycle matched the guide: dev.texture, queue.write_texture, dev.sampler, bind_group with bind_texture/bind_sampler, render_pass closures. The atlas readback worked first time.
- volec test runs -O0 and -O2 and checks they agree.
- Once the compile errors were gone, the headless scenario passed on the first run. The readback checks, SDF property checks and edge-band measurement are the evidence.
- Immediate-mode widgets were simple with `inout` rules clear: no callbacks, no closures.

## 4. What went badly

Compile errors (5 rounds):
1. `constant 'S' has type '[f32]'; constants must be integers, floats, bool or string literals | help: a static array holds them ... static S: [f32; 4] = ...;`. The fix was clear, but I first wrote a const slice, which is what I expected to work. A static table needs the exact length, which I counted with a shell pipeline (608 vs 616 entries).
2. `no method 'clamp' on type 'i64'` and `'abs'`, with std::clamp/std::abs suggested. The integer functions are not in the guide's math section, which covers floats only.
3. `no associated function 'default' in 'Gpa'`: fine as an error; the suggestion (take the allocator as a test parameter) was right.
4. `no 'parse_int' in module 'std::num' | help: did you mean 'parse_f64'?` parse_int is in the prelude; the suggestion pointed elsewhere. Poor suggestion.
5. Rust-spelling `&mut x` at call sites: the hook fixed them with a clear message, one per call site (about 20 messages).

Runtime and logic (3 iterations):
- The atlas report flagged 40/40 glyphs: my thresholds were wrong (the centre-line stores 0.86; corners of dense glyphs store about 0.06). I changed the thresholds.
- Windowed --shot cropped to the top-left quarter: the window is at Retina scale 2, the canvas is physical, and I snapshotted at the logical 800x580. Found by looking at the PNG, not by a checker. Headless-only testing cannot catch this kind of bug.
- The --frames run got no real frame in 3 s (display asleep); the timing is the timer's, and I said so in the README.

Guide and docs gaps:
- No worked textured-quad example: vertex layout with four attributes, R8 texture upload via write_texture, linear sampler bind, textureSampleLevel in WGSL. I assembled it from signatures.
- Color has no constructor in the listings I saw; `gpu::Color { r, g, b, a }` works since the fields are pub.
- `guide --find fwidth`: no paragraph. I used fwidth in WGSL anyway; it compiled and the edges look right visually.
- Mouse and Resize positions are physical pixels (the Mouse doc comment says so); I divided by the scale myself and had to check.

Workarounds: the glyph table as a static with an exact length; no % or , in the font, so UI strings avoid them.

## 5. The language

- What fought me: the inout convention. A let param passes plainly; an inout param needs `&` at the call, and an inout param passed on to another inout function needs `&cv` too. I had to decide, for each parameter, whether it was let or inout. The hook fixed the marks, but this was the main source of new-language friction.
- `let (dev, var queue) = ...`: the var on the second element was needed because write_buffer and write_texture take inout self.
- Closures passed to render_pass captured copies of pipe, group and the buffer; no sink-closure issue.
- Float literals default to f64; I did all layout in f64 and cast to f32 at the vertex push. Natural.
- Text is [u8]; `"..."` works as [u8]; `"vole sdf".bytes()` worked; `as_slice()` on Vec<u8> and Buf.
- Liked: `requires` clauses in signatures; `[..]` on array literals; f-strings with format specs; -O0/-O2 agreement in tests; a small prelude (Vec, format_in, parse_int need no use).
- Disliked: i64 has no methods (clamp, abs) while f64 has many; integer math needs the free functions std::clamp and std::abs, which the guide does not mention.

## 6. Suggestions, ranked by time saved

1. Accept numeric const tables with the length inferred, or document static for numeric tables on the guide's first page. Cost me a round and a shell count.
2. Integer methods (clamp, abs, min, max) like f64's, or document the free functions in the math guide. Two rounds lost.
3. Fix the parse_int suggestion: when a name is in the prelude, say so ("parse_int is in the prelude: drop the module").
4. A worked textured-quad example in guide gpu: four-attribute vertex layout, R8 texture upload, sampler bind, textureSampleLevel. This would have saved most of the discovery queries.
5. Recommend `volec query context` first for std items (I did not try it; query items and show were enough).
6. A HiDPI note in the window guide: physical vs logical pixels for the surface, the canvas and the snapshot. The shipped windowed-snapshot bug was of this kind.
7. Quieter hooks: one summary line instead of one `&mut` message per call site; no "changed on disk" notice after formatter runs.

Numbers: about 8 builds; 5 compile-error rounds; 3 runtime iterations; 1 failing test (my expectation); roughly 85 tool calls. gpu-run waited 0-2.6 s at load 12-29; it never blocked me.

## Files
- Program: main.vl, atlas.vl, glyphs.vl, draw.vl, gfx.vl, ui.vl, demo.vl (folder above). Binary: sdftext.
- Evidence: page.ppm/page.png (headless, 800x580), window.ppm/window.png (windowed, 1600x1160). Tool feedback recorded for: std::num parse_int suggestion, write_texture guide gap, query context not tried.
