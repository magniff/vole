# Feedback: headless254, a scripted event loop for windowed tests and GPU timestamps

2026-10-29, release 0.25.4. New: compiler/std/window/script.vl (the
scripted backend, about 600 lines), compiler/std/capture.vl, std/gpu/capture.vl
(the frame capture), std/gpu/timing.vl (query sets, timed passes,
resolve); changed: std::window's App and Window, std::gpu's Surface,
Frame, Encoder, Commands, Queue::submit, the hal (Caps.timestamps,
submit_timed, gpu_times), index.awk, guide::stdapi's unindexed_section,
the runner's ENV directive; 5 new test cases, 3 goldens, the window and
gpu guides.

## Verdict

The language and std carried the work: an enum backend in App, statics
for what a Window reaches without its App, a child module's `impl` of its
parent's types, and the existing GPUStartTime/GPUEndTime bindings made
both features small and free of new unsafe. What cost the time was std's
lazy-section index (index.awk), which nothing mentions until a build
fails far from the cause, and the transcripts that pin std's shape.

## What worked

- `volec query show A B C` and `query items std::window::keys` for std's
  code: the Cocoa backend, the gpu Surface/Frame and the Metal hal were
  read in four calls.
- The check hook on every std edit: `error[type error] ... bitwise not
  is ~x` and `no 'capture_next_frame' in module 'std::gpu' | help:
  'capture_next_frame' is in std::gpu::capture | try:
  std::gpu::capture::capture_next_frame` were exact.
- `edit patch --pairs FILE` with `@@ NAME` blocks for the five std::gpu
  items one change spans (Encoder, Commands, Device::encoder,
  Encoder::finish, Queue::submit) in one checked call; `edit insert
  --after` for the hal's new Clone and methods.
- `bootstrap/bootstrap.sh --dev --no-suite` (about 20 s) and
  `tests/affected.sh --list`: the plan named the query transcripts and
  the walkthrough that a std module addition breaks.
- `tests/ppmdiff.sh -r X,Y,W,H -o crop.ppm shot.ppm none.ppm` makes a
  golden region in one call (exit 3, "no reference", writes the crop).
- `tests/query/run.sh -u NAME...` and `tests/walkthrough/run.sh -u NAME`
  rewrote the 10 transcripts std's new modules changed.
- The guide's runner (`tests/guide/run.sh -f compiler/guide/window.md`)
  compiled the new section's example in seconds.

## What cost time, ranked

### 1. std's section index: a new std file is core and ungated until index.awk names it

After adding compiler/std/window/script.vl the hook's `volec check` was
clean, and `bootstrap.sh --dev --no-suite` failed in build1:

    <std>:50485:17: error[type error] unknown type 'KeyCode'
    <std>:50493:16: error[type error] unknown type 'KeyCode'

`volec check` runs the release binary on std's files from disk; build1
reads std through the embedded index (compiler/std/index.awk), where a
new module is core (read by every program) and not behind its gate
(`window`), so its uses of the gated keys module do not resolve. Moving
code and deleting comments (I first suspected a `"` in a comment) shifted
the failing lines around for 5 builds (about 25 minutes) before I read
index.awk. Then: std::gpu and std::window are CLOSED gates and cannot
name each other, so the frame-capture request had to become a module of
its own (std::capture, lazy, ungated). And the file's header comment
sits in the module's core section: every program lexes it (moved below
a banner). Nothing in the guide (`guide how`) or embed.sh says any of
this. What would have saved it: embed.sh (or the check hook on a std
file) warning "section std::window::script of the closed gate window is
not in index.awk's LAZY", and a `guide how#adding-a-std-module`.

### 2. The std guide's size limit, and the rule that keeps a section out of it

`tests/guide/run.sh` failed: `guide-std-index: volec guide std --whole
is 21799 bytes (21500 at most)`. The private modules' `pub fn`s (which
std::window and std::gpu must call) were listed in std's index. The rule
that leaves a section out is a list of banner substrings in
compiler/src/guide/stdapi.vl's unindexed_section ("(0.23)", "Math: ",
...); I added "Windows: " and "Frame capture (". Found by reading
std_api's 340 lines (about 15 minutes). A `#[doc(hidden)]`-like marker
on a module, or "a module declared without pub is not in std's index",
would have needed no compiler change.

### 3. Transcripts that pin std's shape

Adding four std modules and one `mod capture;` line failed 9 query
transcripts and 2 walkthroughs (`std::gpu::capture <std> N` lines, a
std line moved by one, `callees sum` reaching 224 functions instead of
215 because `Vec<timing::Seg>`'s drop reaches the Metal command
buffer's), and the arena-parser walkthrough's `volec query effects parse
eval` listed my `std::window::script::parse` and its `str::parse<f64>`
instances. To tell mine from inherited ones I built the base in a second
worktree (3 minutes). Fixed by `-u` and by renaming `parse` to `command`
and using `std::num::parse_f64`. What would have saved it: query output
that lists only std modules a program reaches, and `query effects NAME`
leaving std's instances out unless asked.

### 4. edit patch on std: names the tools binary does not know

`target/tools/volec edit delete std::window::script::DIGITS` ->
`try: target/tools/volec edit delete crate::front::own::walk::VISITS`
(the tools binary embeds the release's std, so a new std item has no
name); FILE:LINE worked. In a pairs file, `@@ std::gpu` was ambiguous
and `@@ compiler/std/gpu/mod.vl` said `no file 'compiler/std/gpu/mod.vl'
in the program` although the command-line FILE target works; a block
for `std::gpu::types::BufferUsage` (a `pub mod` of consts) said `OLD 6 is
not in std::gpu::types::BufferUsage; no line is near it` and failed the
whole edit. About 6 calls.

### 5. The hooks around new std files

Reading my own new 620-line std file with grep or sed needed `#
no-query:` each time (the 300-line rule); moving its header comments
below a banner needed `# no-tool:` (a comment between items is no item
for `edit patch`). The hook's suggestion for `mods.bits & !CLICK` was
`mods.bits & !CLICK != 0` (a bool), though the help said `~x`. A program
of mine in the scratchpad was checked with the main checkout's tools
binary (std without the branch's items): 8 false errors on each write.

### 6. Metal facts that decided the timestamp design

A probe (Objective-C, clang) showed: consecutive command buffers start
70 to 400 us apart on the GPU, while one command buffer's
GPUStartTime..GPUEndTime is exact (203 vs 411 us for 1x and 2x a fill);
Apple GPUs sample counters at stage boundaries only. So a timestamp
"between" commands (WebGPU's writeTimestamp) would measure the gap, and a
pass timed as a command buffer of its own measures the pass. Also: two
timed passes that share no buffer overlap on the GPU, so a test must not
check that one ends before the next begins (my first version did).

### 7. zsh and `tests/run.sh =NAME`

`tests/run.sh =gpu-life-script` -> `(eval):27: gpu-life-script not
found`: zsh expands `=word`. A plain filter worked. AGENTS.md could say
to quote it.

## Never used

`refactor` (no renames across files), `rewrite`, `probe` and `reduce` (no
crash to chase: failures were build-time), `query context` (show and
items sufficed for std), `batch`, `undo`, `explain` (runtime messages
like `window.script:` and `gpu.capture:` have no explain entries, as
gpu.* have none).

## Fix list, in order

1. [build] compiler/std/embed.sh warns when a section of a closed gate's
   module (std::window::*, std::gpu::*) is not in index.awk's LAZY, and
   when a module's header comment (its core section) is long.
2. [docs] `guide how#adding-a-std-module`: the `mod` line, index.awk's
   LAZY and GATES, closed gates cannot name each other (a shared ungated
   lazy module instead), header comments below the first banner, the std
   index's unindexed_section, the transcripts to rewrite with `-u`.
3. [tool:guide] Leave a non-`pub` module's items out of std's index (or
   honour a marker) instead of a banner-substring list in stdapi.vl.
4. [tool:edit] `edit patch --pairs`: accept `@@ FILE` as the command
   line does; a block naming a `pub mod` matches the module's text.
5. [tool:query] With the tools binary, a std item new in the tree: say
   "use FILE:LINE (or target/volec)" instead of an unrelated try:.
6. [diag] The bitwise-not fix suggests `x & ~MASK`, not `x & !MASK != 0`.
7. [hook] Check a program outside the worktree with the worktree's
   target/volec when the session works in a worktree.
8. [test] Query transcripts that list std's modules (prelude017,
   syntax015/016/018, views017, explore-unknown-code) could list only
   the modules a program names, so a std addition does not rewrite 10
   files and conflict between branches.
9. [docs] AGENTS.md: quote `'=NAME'` for zsh.
