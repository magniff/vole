# ANALYSIS: sdftext (vole 0.25.2.2)

## 1. Result

Works, headless and in a window. What it does:
- A stroke font (51 glyphs, written as strings in `font.vl`) becomes a signed
  distance field atlas on the CPU at startup: 1536 x 384 R8, 96-texel cells,
  built in about 41 ms.
- Text is one quad per glyph, rotated on the CPU, thresholded with `fwidth` in
  the fragment shader. Rotation and scale work; the edges stay sharp.
- Four widgets (button, slider, text field, scrolling list) with mouse and
  keyboard, state in `Ui`.

Verified, with the commands and their output (`headless.txt`):
- `volec main.vl -o sdftext` builds with no errors and one warning, which I fixed.
- `volec test main.vl`: `7 passed (7 #[test]; -O0 and -O2 agree)`.
- `gpu-run --timeout 60 -- ./sdftext --headless --shot shot.ppm`, exit 0:
  `atlas: 51 glyphs ... stroke middles inside the outline (value > 0.5): 51 of 51`,
  `cell corners outside (value < 0.5): 51 of 51`,
  `widgets: clicks 2, value 0.75, text "HELLO" (5 bytes), list top 6, selected 8`.
  `shot.png` (converted with ppm2png.py) shows the page: title, samples at 12 to
  96 px, tilted and rotated text, the widgets in their state.
- Windowed: `gpu-run --timeout 60 -- ./sdftext --frames 30 --shot win.ppm`, exit 0.
  The snapshot is 1920 x 1280 (scale 2) and shows the same page, crisp.

Not verified:
- Live interaction. The clicks, drag, typing and wheel were fed by the headless
  script through the same `Ui::feed`, not by a person in a window. The window
  path's event mapping (`Event::Mouse`, `Scroll`, `Text`, `Key`) compiles but
  was never exercised.
- Frame times. The display was asleep, so the window reported its 10 fps timer
  (`window: no frame in 3 s`), and 30 frames took 101 ms each. Those numbers are
  not GPU timings. The headless run was not timed as a benchmark.
- The "lit pixels" counts in the headless output are a rough statistic (byte
  count over 3), not a test.

## 2. How you worked

- Learning: `volec guide` (the core, about 2k tokens), then `volec guide gpu`
  (long, about 8k tokens), `guide window`, `guide gpu-render`. `volec guide
  --find` and `guide TOPIC#SECTION` were not needed. I read the reference
  programs (fluid2d's `main.vl`, `sim.vl` draw and snapshot, `ui.vl`, `font.vl`).
  Reading fluid2d was the most useful step: its idioms for `inout Encoder`,
  `snapshot_in` and the window loop were copied almost whole.
- Queries: `volec query show` on std::window's `Event`, `Mouse`, `Scroll`, `Text`,
  `Key`, `Named`, `Logical`; `query items std::gpu` (a long list, mostly
  signatures with the `requires` contracts inline); `query show` on `Device` and
  `bytes_of_f32`. About 6 query calls in all. I did not use `query context`,
  `edit patch`, `refactor` or `fix --suggested` on purpose: I wrote whole files
  with Write and edited with a Python script (`str.replace` with an assert).
  Roughly 15 Python edit scripts, which is how most fixes went.
- Builds: about 16 `volec main.vl -o` runs, about 9 of them failing; 6 `volec
  test` runs (2 deliberately failing, to see values, see section 4); 4
  `volec fmt` / `fix` runs.
- Hooks: the check hook reported the errors after each edit and its `try:` lines
  were correct when they existed (`edit patch main.vl:50 --old '(queue' --new
  '(&queue'`). The automatic fix rewrote my `use std::{env, gpu as gpulib}` into
  two lines and removed an unused import; it did not get in the way.
- `tools/agent-feedback`: 4 lines recorded (see section 4).
- Wall-clock: the headless run that waited for the GPU lock waited 0 s in most
  runs. Once, at the start of the windowed work, gpu-run waited 119 s with load
  2.8 (one line, not a blocker).

## 3. What went well

- The GPU side worked on the first run: one pipeline, a Bgra8Unorm target, an
  R8Unorm atlas sampled with `textureSampleLevel`, `fwidth`, `smoothstep`,
  `select` all passed the WGSL translator unchanged. No WGSL or Metal bug.
- `Blend::alpha()` and `VertexLayout` with four attributes at a 36-byte stride
  worked as documented.
- Compile errors, once read, were specific. `conv.marker ... mark it '&queue'`
  and `own.readonly ... declare it var` each gave the exact edit.
- The compile was fast enough to fix one error per build; I did not time it.
- Passing `dev` as a let parameter and not storing it worked once understood:
  the Renderer kept only pipeline, bind group and buffer.
- The atlas is a plain `Vec<u8>` built with a `for` loop; no GPU compute was
  needed for it, and the CPU build is 41 ms.

## 4. What went badly

Compile and language errors, with counts (I counted the failing builds):

1. `main.vl:37:26: error[parser error] 'inout' is a keyword (...): a name cannot be
   spelled so`. My parameter was written `fn snapshot(r: Renderer, inout queue:
   gpulib::Queue, ...)`, and then `fn script(inout ui: Ui, ...)`. The right form
   is `queue: inout gpulib::Queue`. The message names the wrong thing: "a name
   cannot be spelled so". It should say "a parameter's convention goes after the
   name: `x: inout T`".
2. `gpu.vl:8:1: error[parser error] a use names an item through a path: 'use
   module::item;'`. The real problem was a module called `gpu` (my file) next to
   `std::gpu`. The message points at the `use` line, not at the name clash.
   The help text suggests `use crate::...`, which fixed it, but the clash itself
   was not named.
3. `no method 'and_then' on type 'Result<Adapter, Error>'`. Result has no
   `and_then` (I guessed Rust's). The `try:` line only suggested `query items Result`. I rewrote as a helper `fn open(inst) -> Result<...>
   { inst.adapter()?.device() }`.
4. `ui.vl:275:22: an f-string is a 'std::Interp' (a value that prints), not '[u8]'`.
   The fix is `format_in(f"...", gpa).as_slice()`, but it needs a `gpa` in scope,
   and a widget method has none. I added a `gpa` field to `Ui`. A `Buf` from
   `format_in` the guide mentions is the only [u8]-making route; I found it
   only through the error's `help:`.
5. `own.move_out: cannot move 'dev' (Device) out of a reference ... ('Device' has no
   '.clone()')`. My Renderer stored the Device. The fix was to stop storing it
   and pass `dev` as a let argument. The message is clear; the cause (let
   parameters lend, and `Device` cannot be copied) is not stated anywhere I read.
6. `conv.place: '&' lends a place for the callee to change; 'mut_r()' is a
   temporary` — my typo (an invented name, left in by a bad edit). Not vole's fault,
   but the error gave a suggestion ("name it first") that I should have followed.
7. `own.readonly: 'r.record(...)' changes 'r', a let binding` — I had written `let
   r` and `record` takes `inout self`. Clear message; my mistake.
8. `error[type error] an f-string is ...` (item 4) and `error[type error] undefined variable`
   (the typo) — listed above.
9. `volec test` does not show `println` output in the terminal. A passing test
   with `println` prints nothing I could see, and the output went to
   `.volec/test/O0/*.got`. I found the values only by making the test fail on
   purpose (`assert_eq(b, 999)`, which printed `b = 188`). The docs (`guide
   testing`) do not mention where test output goes.

Time sinks (attempts):
- The atlas check: my test said "1 of 51 glyph midpoints above 0.75". It was
  not a bug: a sample taken off the stroke's exact centre gives 0.59 to 0.75.
  Diagnosing it took 4 test runs (3 with deliberate failures to read values). A
  `println` in a test would have saved those.
- The overlapping glyphs: a double `k` scale in `Canvas::text` (`pen` was
  already in pixels). Visible in the PNG, not caught by any check. A headless
  check of glyph advance would catch it.
- The layout: the page needed three layout rounds to stop collisions. Fine, but
  the page has no bounds check, so overlaps are silent.

Guide/doc gaps:
- No guide section on how a widget or a method gets a `gpa` for an f-string
  (`format_in`), or how to build a `[u8]` label without one.
- The `Device` ownership rule: the guide's lifecycle section says every object is
  owned and dropped at scope end; I did not find an explicit statement that a
  `Device` cannot be stored in a struct that is only lent. The error says it.
- `volec guide gpu` is about 8k tokens. The part I needed (the window loop and
  the render pass) is in the first section; the rest is long for an agent that
  only needs the basics.

Tool feedback (recorded with `tools/agent-feedback`): the `gpu.vl`/`use std::gpu`
clash, the `inout` parameter message, the f-string-as-[u8] message, and `Result`
having no `and_then`.

## 5. The language

What fought me:
- Parameter conventions: `x: inout T` and `&x` at the call. I used the wrong
  order twice and read the error as a keyword problem. Rust's `&mut x` habit
  made `inout` the wrong guess.
- Let parameters lend and cannot be stored. Good, but it makes a struct that
  holds a `Device` impossible without ownership planning, and I needed the
  pattern to pass `dev` around by hand.
- f-strings are not text. Every label that shows a number needs `format_in` and
  an allocator, which means a `gpa` in every widget. That is the largest friction
  for an immediate-mode UI: the widgets all need the allocator.
- No `Result::and_then` (the others I did not test).
- `[[u8]; N]` consts (the font's glyph table, the fruit list) compiled exactly as
  written and were convenient: a `"char strokes"` string per glyph, parsed by a
  small byte loop. Good.
- `Vec::clear`, `Vec::pop`, `Vec::push`, `as_slice`, `clamp` on f32, `sqrt`,
  `cos`, `sin` all existed as expected.
- `assert_eq(a, b)` in a `#[test]` with a `gpa: Gpa` parameter worked.

What I liked:
- The windowed and headless code share everything but the entry point; the
  `Renderer::record` and `Ui::page` are the same in both.
- The compile is fast enough that fixing one error per build is cheap.
- Errors that name the fix (`mark it '&queue'`, `declare it var`, `name it
  first, then lend it`) got me out of trouble within one turn.

## 6. Suggestions, ranked by time saved

1. Print from `#[test]`: show `println` output in the terminal or in the failure
   block. Saved me about 4 runs. (Would also help every test that checks numbers.)
2. A `format_in`-free way to make a label: either `Buf::as_slice` on an f-string
   in a `[u8]` position, or a documented `fmt_in(gpa, ...)`. The gpa in every
   widget was the largest friction.
3. Name the real cause for the module/`std` name clash (item 2 above).
4. Say which convention spelling is right in the `inout` error: "`x: inout T`,
   after the name".
5. Explain why a `Device` (or any handle) is not storable in a struct that is
   lent. A one-line note in `guide gpu`'s lifecycle table would have saved a
   turn.
6. `Result::and_then` or a list of Result's methods in the "no method" error.
7. A `query` that shows the glyph advance or layout is not needed; a test
   helper that asserts "these texts do not overlap" would have caught the
   double-scale bug.

Numbers: about 16 `volec main.vl` builds (9 failed), 6 `volec test` runs (2 of
them failing on purpose), 4 formatter/fix runs, about 15 Python edit scripts,
about 6 query calls, 1 headless run that waited 119 s for the GPU lock early on
(load 2.8), and the later GPU runs waited 0 s. Final sources: 1145 lines of vole.
