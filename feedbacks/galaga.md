# Tooling feedback: porting neural-galaga to Vole

What: a from-scratch port of the Rust `neural-galaga` agent (simulation, 368×288
software framebuffer, Burn checkpoint loading, inference, saliency, wgpu blit) to
`examples/gpu/galaga/` — 5,029 lines over 10 `.vl` files, verified against Rust
by hashed observations, frame hashes and a policy-value bit pattern.

Written by the agent that did the port, on 2026-10-27, from what it actually
ran. Ordered honestly: praise first, then cost, then the fix list.

## Verdict

The compiler tooling is the best part of this repo. The navigation tooling is
good but assumes you are editing `compiler/`. The language-learning tooling has
a hole exactly where this work happened: GPU and WGSL. A port workload uses
about five commands, so judge changes on that path too, not only on
compiler-maintenance.

## What carried the work

- **The `check-after-edit` hook.** `volec check main.vl` on the galaga program
  takes **0.12 s** (`time target/tools/volec check main.vl`). That is why the
  loop was tight: checking is never a decision, and the "N new errors, N fixed"
  diff distinguishes a regression from fallout without reading output. Best
  design decision in the agent tooling.
- **`query context NAME`.** Learned std from it (`IntVec`, the C-math wrappers,
  `Xoshiro256pp`) and the call shape of `examples/gpu/life`'s GPU setup, without
  reading files. It genuinely replaces show + refs + def.
- **`query text FILE:A-B`.** Cheap and exact; this is what actually got used for
  reading. `query show FILE` caps at 200 lines, so ranges win on anything real.
- **The diagnostics themselves.** Right about 90% of the time, at a line that
  could be fixed in one edit: `distinct`, `own.move_out`, unused variables, the
  "no such field" family. All one-shot fixes.
- **`tools/agent-feedback`.** Recording the `-O2` for-loop segfault took one line
  at the moment it was reduced — the right shape for a bug channel.
- **`tests/run.sh FILTER`.** Fast, and `-O 0` runs caught the -O0/-O1 divergence
  class without ceremony.

## What cost time, ranked

### 1. No `guide` topic for the GPU surface (WGSL, storage buffers, bind groups, surface formats, window descriptors)

`guide --find "index buffer"` and `--find indirect` returned nothing useful (both
filed via `agent-feedback`). The GPU examples were the only documentation: I read
`examples/gpu/life/{main,view,check}.vl` end to end and grepped `book/`. Then a
shader that is valid WGSL was rejected by the Metal frontend because a helper
named `quad` collides with a reserved Metal type — a **runtime panic on a shader
error**, the worst place to find it.

This was the largest learning cost after the port itself, and it is structural:
examples are the only docs for an API made of positional descriptor structs.

### 2. Float-literal inference failing far from the cause

`let col = if c { [...] } else { [...] }` produced **seven errors at lines
423–471** of `render.vl`, none of them at the `let`. In a numeric port nearly
every constant is a float, so the `f64` default tax was paid repeatedly. The hook
reported all seven faithfully, but it cannot say "this is one mistake". A note at
the definition ("element type inferred `f64` here; annotate `[f32; 4]`") would
have collapsed seven round trips into one.

### 3. `query`/`edit` program-root scoping

Every query from the repo root against an example fails, and the `try:` line
suggests a command that also fails from the root:

```
$ volec query items examples/pathtrace/render.vl
error query.bad-root: cannot read 'examples/pathtrace/render.vl'
try: target/tools/volec query items            # no argument at all

$ volec query items crate::model
error query.no-match: no module 'crate::model'
try: target/tools/volec query items            # ditto

$ volec query context examples/gpu/galaga/model.vl:1
error query.no-match: no item at examples/gpu/galaga/model.vl:1
try: target/tools/volec query items crate::model   # only works after cd
```

Workaround every time: `cd examples/gpu/galaga && /abs/path/target/tools/volec
…`. This is the most *repeated* friction, and it makes the tool feel unreliable
in `examples/` — the directory the language is sold on.

### 4. Unused imports are invisible, even under `--deny-warnings`

Verified during this session:

```
$ printf 'pub fn x() -> i64 { 1 }\n' > b.vl
$ printf 'mod b;\nuse b::x;\nfn main() -> i32 { 0 }\n' > a.vl
$ volec --deny-warnings a.vl -o a.out
ok: built a.out        # exit 0; the import is unused
```

I shipped `Window`, `blit_game` and `draw_hud` unused until re-reading the file by
eye. `compiler/src/front/modules/lookup.vl:275` says unused imports are checked
"too" — either that signal is dropped or the check is not implemented. In a
10-file port this is exactly the rot nobody notices.

### 5. A wrong `try:` on `distinct.mix`

`["examples/gpu/galaga/checkpoints/best.mpk"].default(MODEL)` where `MODEL:
[u8]` suggested `str::from_utf8(MODEL)?`, which is not the fix (inlining the
literal was). One bad suggestion costs more than five silent ones, because from
then on every suggestion gets audited before it is trusted.

### 6. No known-issue surface

The `-O2` segfault (a `for c in 0..14 { v[801+c] = 1.0 }` late in a function) cost
a real detour: reduce to `for` vs `while`, confirm -O0/-O1 are fine. There was no
way to ask "has anyone seen this?" — `agent-feedback` is write-only for the agent.

### 7. `edit patch` exactness

Multi-line `--old` needs byte-exact indentation, and when a whole function has to
be rewritten the fallback is `write` — which the hook still checks, so the
"checked edit" advantage disappears at that size. Worth documenting that `edit
patch` is for surgical single-hunk changes, not a bulk-edit primitive.

### 8. Small, but in the hot path

- `tests/run.sh -O0` exits **2** and dumps 36 lines of usage to stderr; `-O 0`
  (with a space) is the form. No "unknown flag, did you mean `-O 0`" line.
- `fmt --all` reformatted `examples/gpu/life/check.vl` (import order), unrelated
  to the change: noise in a focused branch that cost a judgement call about what
  to commit.

## What was never touched

`refactor rename|move|signature|field|variant`, `rewrite`,
`extract-function|inline|split`, `batch`, `undo`, `impact`, `effects`, and
`query def|refs|callers|grep` beyond one probe each.

Not a complaint, a shape statement: a port uses roughly five commands —
`check`, `query context`, `query text`, `query items`, `fix`, plus
`tests/run.sh`. The toolset is compiler-maintainer-shaped. Fine — but judge
improvements on both paths.

## Fix list, in order

1. **Auto-discover the nearest `main.vl` for `query`/`edit`, plus `--root DIR`,
   and put it in every `try:` line.** Fixes the most repeated failure; small.
2. **An unused-import diagnostic.** Warning by default, error under
   `--deny-warnings`.
3. **A definition-site note for float/int literal inference** when the inferred
   type flows into a mismatched parameter — or a lint on `if`/`match` arms whose
   array literals unify to `f64`.
4. **`guide gpu`:** one canonical window + buffer + compute example, the
   descriptor structs, surface formats, and "WGSL is compiled by the Metal
   frontend; here is what it rejects".
5. **`fmt --changed` / `--since REV`.**
6. **`tests/run.sh`:** accept `-O0`; hint on an unknown flag instead of dumping
   usage.
7. **`agent-feedback --list` / `--find`**, mentioned in `AGENTS.md`.

## Instrumentation gap

`.git/agent-tools.jsonl` records only query-shaped events (`query`,
`query-result`, `escape`, `blocked`, `feedback`, `hint`, `turn-end`). Writes,
edits, builds and test runs are absent, so for this session the log holds ~34 rows
for a multi-day, 5k-line port. `tools/agent-tool-usage.py` therefore cannot say
where a *port* spent its time — only where compiler maintenance spends it.
Logging every tool call with duration and exit code (the hook already sees them)
is cheap and would make the next retrospective empirical instead of recollected.

## One line

The checked-edit loop is genuinely excellent and the compiler's `try:` lines are
the best I have driven; the two things holding the experience back are that
navigation does not know about program roots in `examples/`, and that the
language guide stops at the CPU.
