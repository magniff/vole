# Tooling feedback: the pathtrace laboratory UI

What: rebuilding `examples/gpu/pathtrace` as a scene-driven path-tracing
laboratory with an on-screen immediate-mode panel — four scene presets,
fog/light/material/camera controls, a 5×7 bitmap font, a blended UI pass and a
headless `--ui` screenshot path. About 2,000 new lines: `ui.vl` 834,
`ui_panel.vl` 449, `ui_render.vl` 69, `font.vl` 99, `ui.wgsl` 29, plus `state.vl`
rewritten (511), `main.vl` (542), `check.vl` (+60), and changes in `trace.wgsl`
and `display.wgsl`. The example is 3,646 lines including the pre-existing WGSL.

Written by the agent that did the work, on 2026-10-29, from what it actually
ran. Ordered honestly: what carried it, what cost time, then the fix list.

## Verdict

The compiler loop is still the best thing here: `check` at **0.15 s**, `test`
at **0.05 s** over 12 tests at -O0 and -O2, exact `try:` lines for every mistake,
and a headless GPU path that made visual verification possible. What held this
work back was not the compiler but the platform around it: Vole has no UI or
text primitives, no allocation-free float formatter, and no sanctioned way for
an agent to see a windowed program's pixels. The first two are std/std-docs
gaps; the third is an example-harness gap. All are smaller than the UI itself.

## What carried the work

- **`guide gpu`, `guide gpu-render`, `guide window`.** Current for 0.25.3 and
  accurate enough to design the UI pass from: `PassDesc::color(view, load:
  Load::Keep)` makes an overlay a load instead of a clear, and the texture /
  sampler / vertex-buffer sections had the shapes I needed. `guide window`'s
  event and surface-size sections were the difference between pointer
  coordinates that work and a UI that is off by the display scale.
- **`query show` for the exact std contract.** `query show PassDesc`,
  `RenderDesc`, `Load`, `Blend`, `VertexLayout`, `Surface`, `fmt_i64` and
  `query items std::Vec|std::math` answered the questions the guide only
  sketched. The six-line contract at the top of a `query show` is the
  right amount of documentation to act on.
- **`check` and its `try:` lines.** `conv.mode_order` ("a parameter's mode goes
  after the colon") and `conv.rust` ("`let mut` is Rust's spelling") were each
  one edit, with the corrected line ready to paste. The error is at the line
  that is wrong, not at a caller.
- **`volec test FILE`.** `#[test] fn name(gpa: Gpa)` is the right shape for
  examples: state clamping, scene switching, camera bounds, panel hit-testing,
  slider drags, combo deferral and the panel footprint all run in 50 ms at both
  optimization levels. The -O0/-O2 agreement line is free confidence.
- **`RawSurface::Headless` + a new `--ui` path.** The single most valuable
  technical lever in the session. Because the example already renders through
  `std::gpu` into a surface, I could add a `capture_ui` that runs the *real*
  panel draw list through the *real* UI pipeline and read back the composite.
  That is how every layout bug in this report was found. No CPU renderer, no
  screenshot tool, no window server needed.
- **`tests/run.sh pathtrace`, `tests/affected.sh`, `tools/premerge.sh`.** The
  five pathtrace cases, the affected plan (`5 of 2765`, 74 cases at -O0, 5 at
  -O2) and `premerge: ok` are exactly the tiering `AGENTS.md` promises. Nothing
  about the change required a full suite to be useful.
- **`target/volec fmt`.** It caught import order and line wrapping in the new
  files before the commit hook could. `premerge` then had nothing to say.
- **std's math methods.** Rewriting the camera's C `math.h` calls as
  `f64::sin/cos/asin/sqrt/abs` removed eight `unsafe` blocks from a file I was
  already touching, and the tests still passed. This is the "try the safe way
  first" path working.

## What cost time, ranked

### 1. There is no text or UI layer in std, and examples are the only precedent

An immediate-mode panel needs hit-testing, clipping, hover/active state,
sliders, a dropdown, a font and a textured-quad pass. I wrote all of it. The
5×7 font is copied from `examples/gpu/fluid2d/font.vl` because there is no
other font in the tree; the atlas builder, glyph UVs, blending, vertex layout
and text measurement are new. That is roughly 1,000 lines before the panel has
a single control on it. The fluid2d overlay is a cell-grid text blitter, not a
widget toolkit, so it was a starting point for the font only.

This is not a request to put Dear ImGui in std. It is a request for the two
primitives every such program needs: a way to draw a textured quad over an
existing target (documented, with `Load::Keep` and `Blend::alpha`), and a text
measure/draw pair for a bitmap atlas. A 40-line `guide gpu-render` section
"drawing over the image you just made" plus a 30-line "text from an R8 atlas"
snippet would have saved most of a day of API archaeology.

### 2. No allocation-free `f64` formatting for UI text

`f"{v:.1}"` exists for `println` and `format_in`, but a panel that draws a
number per slider per frame cannot allocate a `Buf` for each. `fmt_i64` gives
integer digits into `[u8; 20]`; there is no f64 equivalent. I wrote
`format_fixed` (round, sign, fixed decimals, into `[u8; 32]`) and a unit test
for it. It is 45 lines that every graphical Vole program will write again.

A `std::num::fmt_f64(v, decimals, out) -> start` (or `Buf::push_fixed`) next to
`fmt_i64` is the smallest, highest-leverage std addition from this session.

### 3. `Surface` has no `scale`, but the window guide talks about it there

`guide window` says: "On a Retina display (`scale` …). Configure the surface
with that size (`surf.configure(dev, s.w, s.h, ..)` …), so `surf.width` and
`surf.height` are the drawable's pixels too … Divide by `scale` only for logical
points". The scale is on `window`'s `Size` struct, not on `Surface` — `query
show Surface` confirms `{ raw, configured, width, height, format }`. I tracked
`var scale = pixels.scale` and updated it on every `Resize`; the first version
read `surf.scale` and failed at compile time. Either add `Surface.scale`
(set by `configure`) or move that sentence to the `Size` struct in the guide.
A UI is exactly the code that needs both numbers in the same frame.

### 4. The type-inference tax lands on layout code

Three classes repeated while writing new code:

```vole
// f64 by default, so the two arms do not unify:
let bg = if down { ACCENT_DIM } else if hovered { [0.20, 0.52, 0.70, 1.0] }
    else { [0.10, 0.30, 0.42, 1.0] };   // [f32; 4] vs [f64; 4]

ui.begin(...);                            // input struct literal: fine
fn key_shortcuts(inout lab: Lab, ...)     // conv.mode_order: it is `lab: inout Lab`
let mut cx = x;                           // conv.rust: it is `var cx`
```

Every diagnostic is correct and suggests the fix, but each is a round trip in a
file being written at speed. The first one is the expensive class: the error
names both branches, not the `let`, and in a theme file with a dozen colour
constants it recurs. A note at the definition ("this array literal inferred
`f64`; annotate `[f32; 4]`") or making untyped array literals adapt to the
other arm would turn a family of errors into one lesson.

### 5. No way to see a windowed example's pixels from an agent session

I launched the real window for a five-second smoke test and it ran clean, but a
GUI screenshot is not available to the harness. The `--headless` readback path
existed for checks; I extended it with `--ui`, `--ui-section N` and
`--ui-scale S` so the panel could be rendered through the window's own pipeline
at 1× and 2× and inspected as a PPM. That is now the example's visual test, and
it should be a documented pattern, not an invention per example: "a windowed
example gets a `--headless` mode that renders its final frame; `--ui` renders
the overlay too".

Without it, "verify visuals by running" is not possible for an agent, and the
review would have been a compile check plus hope. With it, I found clipped scene
taglines, footer buttons overlapping the last card, a header stat hidden under
the HIDE button, and overlapping material labels — all in one pass.

### 6. Bulk edits bypass the check-after-edit hook

I wrote the new files with the write tool (hooked) and then iterated with
Python heredocs for multi-line layout changes (not hooked). The hook correctly
did not fire for shell writes, so `check` was manual during those stretches.
For a compiler source file that would be against the rules; for an example it
is allowed, but it means the inner loop is only as tight as my discipline.
An optional `volec watch FILE` (or a hook that watches shell writes under
`examples/`) would close the gap without changing the policy.

### 7. `unsafe.unjustified` is background noise in this example

`render.vl` has five pre-existing `unsafe` blocks without `// UNSAFE:` /
`// SAFETY:` comments; every `check` prints them, so a *new* unsafe block would
not stand out. This change added none (the C math calls became `f64` methods),
so the warning count stayed at five and I could ignore it. A one-time cleanup of
the example, or a per-file baseline, would make the signal usable again.

### 8. Panel tests want private state

The UI's active widget, open popup and vertex list are implementation details,
but the tests that matter (a drag sets the value from the pointer, a click needs
press and release on the same widget, a combo chooses on the next frame) need
to read them. I first wrote test-only accessors in a second `impl Ui`, then
replaced them with public fields; either way the test grows the module's API or
adds indirection. `guide testing` says tests get a `gpa` but not what a test in
the same file can see; one sentence on private-field visibility would settle
whether a widget test can keep the draw list private.

## What was never touched

`refactor`, `rewrite`, `extract-function|inline|split`, `batch`, `undo`,
`impact`, `effects`, `query context|refs|grep|def` beyond none this session. A
new-code workload uses `guide`, `query show|items`, `check`, `test`, `fmt`,
`bootstrap.sh --dev --no-suite`, `tests/run.sh`, `tests/affected.sh` and
`premerge.sh` — about nine commands. That is the same shape as the galaga
report: the toolset is excellent on the path it was built for, and the gap is
in what examples need to be *seen* and *written*, not in the compiler.

## Fix list, in order

1. **`std::num::fmt_f64(v, decimals, out) -> start`**, allocation-free like
   `fmt_i64`, with the same tests. Every graphical program needs it.
2. **A `guide gpu-render` section for an overlay pass**: `Load::Keep`,
   `Blend::alpha`, one textured quad, `write_texture` of an R8 atlas, a vertex
   layout with position/colour/UV. This is the recipe I reconstructed from
   `query show`.
3. **`Surface.scale`** (set on `configure`) or move the scale sentence in
   `guide window` from the surface to the `Size`/`Resize` event.
4. **Document the headless visual pattern** next to `RawSurface::Headless`:
   render, read back, optionally run the overlay, write a PPM; a `--ui` mode in
   the examples that have one. "Verify by running" needs a pixel path an agent
   can run.
5. **A definition-site note for array-literal inference** (or adaptive untyped
   array literals) so an `if` with `[f32; 4]` and `[f64; 4]` arms points at the
   literal, not at two far-apart lines.
6. **`fmt --changed`**, and format-on-write for `.vl` files the way
   `check-after-edit` runs `check`; new files should not wait for `premerge` or
   the commit hook to be formatted.
7. **Clean the example's pre-existing `unsafe` warnings** once, so the next
   unjustified block is visible.
8. **Say what a `#[test]` in the same file can see**, or allow it to see the
   module's private fields; a widget test should not have to make the draw list
   public.

## Instrumentation gap

The agent log records query-shaped events, but this session's loop was mostly
`shell` (grep/wc), `write`, Python and `sips`; the log cannot show that the
UI pass took two rounds of `query show` and one of `guide`, while layout took
most of the wall time. Logging every tool call with duration and exit code (the
harness already sees them) would make the next retrospective empirical, as the
galaga report also asked.

## One line

The compiler and its checked loop are genuinely excellent; the two things that
shaped this work were that Vole has no text/UI primitives and no allocation-free
float formatter, and that an agent cannot see a windowed example's pixels
without inventing a headless overlay path — both fixable in std and docs, not
in the compiler.
