# sph: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message (between its `=== ANALYSIS.md ===` markers): the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note.

## 1. Result

Works:
- Builds with std only, no C, no build script.
- GPU counting sort by cell plus exclusive prefix sum (one workgroup, tile loop over 561 tiles of 256 cells) match the CPU exactly: 0 differences over 143,641 cells and 102,400 particles. Order is a permutation sorted by cell.
- SPH step (density, pressure, viscosity, rotating box walls) on the GPU. Bulk mean density settles to 0.987 of rest after 8000 steps (0.64 s sim); max speed 10.7 m/s (below the 20 m/s sound speed).
- Headless default run exits 0, all verdicts ok. `volec test main.vl`: 4 passed at -O0 and -O2.
- Window runs (`--frames 300`, 15.75 ms/frame at 16 steps/frame, via gpu-run); the frame checked as an image.

Not verified:
- The mouse. No real input was sent, so stir and tilt by mouse/arrows compile and run their code paths but their feel is untested.
- Speed: 16 steps/frame is about 1/12 real time. Real time would need ~130 steps/frame at this step size. The limit is the sound speed (c ~10x fluid speed) and ~0.85 ms/step at 100k particles.
- All-particle mean density reads 0.92 (free-surface particles lack neighbours). The check uses the bulk mean (particles at >=90% of rest) with a 5% threshold; both choices are mine.

Verification: `volec test`; `./sph --headless` (default); `./sph --frames 300` via gpu-run; shot read as PNG. CPU checks compare the GPU read-back against a CPU histogram, CPU exclusive scan and CPU cell function computed from the same positions: exact comparison.

## 2. How you worked

About 65 tool calls. Read first: `volec guide` (full), `guide gpu`, `guide window`, `guide testing`, `guide --find atomic/workgroup`; fluid2d's main.vl and sim.vl via `volec query text` (cat was blocked by the hook); `query items std::gpu`, `query items std::window::keys`, `query context Sim::new_in`, `query grep`. Used `query` 9 times; never `query refs`, `impact`, `edit patch`, `refactor`, `volec fix --suggested`. Writes were Write/Edit (multi-line WGSL and vole). Builds ~10. `volec check` after each edit (via hook) was the most useful loop: it reported all 7 errors of my first file at once. gpu-run ~9 times, 2-10 s each.

Failed attempts (clean builds, runtime/logic failures):
1. Shared 10-entry bind group: `sim.vl:135:17: gpu.layout: a bind group has one entry for each binding of its layout: entries.len() = 10, layout.count = 2`. A kernel's layout keeps only the bindings its code uses. Fix: one bind group per kernel with exact entries. 1 run, ~3 turns.
2. First physics run blew up (density 216x rest, speeds 26,000 m/s). My error: STIFF = c^2*rho0 (4e5); with density as mass per area, p = c^2(rho-rho0) so STIFF = c^2 = 400. 2 runs, ~6 turns.
3. Blow-up at 27-30 m/s: tilt sine of 6 rad per sim-second moved the walls at ~5 m/s, faster than the fluid; the window tilt was paced in real seconds (25x faster in sim time). Fix: tilt paced in sim time, slower headless tilt. 3 runs, ~8 turns.

Hooks: query-first blocked 4 commands (sed -n and cat of a .vl, a grep over .vl, a Python script rewriting .vl; I then used Edit). Each cost a turn. The check hook was good. `volec fix --suggested` changed nothing I needed.

## 3. What went well

- Atomics and workgroup memory worked first time: `atomic<u32>` storage, atomicAdd/Load/Store, `var<workgroup>` with workgroupBarrier in a tile loop. Sort and scan correct on the first GPU run.
- WGSL-in-a-string pattern: `pub const K_BIN: [u8] = "..."`, joined with Buf, one shader per kernel, shared PARAMS part.
- `volec check` after each edit: every error at once, exact line:column, try: lines.
- Vec, Buf, format_in, parse_int, the window and gpu APIs were easy once fluid2d showed the shape.
- `#[test]` with `gpa: Gpa` and assert_eq worked. Checked indexing meant no crash to debug. No unsafe.

## 4. What went badly

Error messages that confused me (quoted):
- `error[parser error] expected identifier, got '..'` for `Frame { ..f }` (struct update). No hint vole has none.
- `error[type error] no associated function 'default' in 'Gpa'` for `Gpa::default()` in a test. Right form: `fn t(gpa: Gpa)`.
- `error[type error] expected '[u32]', got '[i64; 5]'` for `let xs: [u32] = [1, 2, 3, 0, 4];`. Literal ignores the annotation. `let xs: [u32; 5] = [...]` plus `xs[..]` works. The suggested `[1,2,3,0,4][..]` would stay i64.
- `no 'parse_i64' in module 'std::num' | did you mean 'parse_f64'?` Wrong suggestion; prelude `parse_int` is right.
- `gpu.layout: ... entries.len() = 10, layout.count = 2` (see 1). Does not say which bindings the layout kept.
- `an f-string is a 'std::Interp' ... not '[u8]'`. Good; help line right.

Docs/std missing or wrong:
- No std::math: no sin, cos, sqrt, floor for f32/f64. I wrote Taylor sin/cos, Newton sqrt, floor by truncation (~25 lines). `guide std` does not say so; fluid2d has the same workarounds.
- guide gpu#bind says "one entry for each binding of its layout" but not that a layout keeps only used bindings.
- testing guide shows `gpa: Gpa` for tests but nothing on how to get one otherwise.

Time sinks: bind group ~3 turns; STIFF units ~6; wall speed ~8. The physics ones were my mistakes, but a blow-up prints only "mean density 216 x rest" and a speed; a "largest speed and where" line helped.

Compiler, std, or WGSL bugs: none found.

Harder than Rust/C:
- No sin/cos/sqrt in std (Rust: f32::sin).
- No struct update (`..f`): fields set one by one.
- Integer literals in an array with a slice annotation do not infer u32; I had to name the array length.
- `for x in xs` gives a value; `*x` is for raw pointers (I wrote it once from habit; the error was clear).

## 5. The language

Fought me:
- Allocation threading: `Vec::new_in(gpa)` / `Buf::new_in(gpa)` through ~12 helpers. Explicit and correct, but noisy.
- Per-kernel bind layouts: I wrote 7 bind groups with exact entries. That's wgpu's rule, inherited; the error is the least helpful part.
- Hook blocked reads of small .vl files (a 150-line file is not a case to refuse).

Liked:
- `inout` and `&x` at the call: `s.step(&enc)` reads clearly, nothing copied.
- Atomics and shared memory with barriers in shader strings, no setup.
- `match` on `Logical::Char(c)` and `Named::ArrowLeft`; f-string format specs (`{x:.4}`, `{n:>6}`).
- Checked indexing hid nothing here; `query text` reads a 500-line example in parts.

## 6. Suggestions, ranked by time saved

1. std::math: sin, cos, sqrt, floor, exp, pow for f32/f64 in pure vole (already planned). Biggest saving: ~25 lines of my own plus a wrong-shaped floor.
2. Bind group error naming the layout's bindings and saying a layout keeps only the bindings a shader uses (or an entries map keyed by binding). ~3 turns and a guess.
3. Parse hint for `..` in a struct literal ("no struct update; set the fields"). ~2 turns.
4. Correct did-you-mean for `parse_i64` (`parse_int` is the prelude name). ~1 turn.
5. Array literal takes the slice annotation's element type, or the error suggests `[u32; N]`. ~1 turn.
6. query-first hook: allow sed -n / cat of a range or of files under ~200 lines, or give the reason in the block. ~3 turns across the session.
7. Testing guide: note how to get a Gpa in a test next to the missing Gpa::default. Under 1 turn.

Feedback recorded via tools/agent-feedback (5 lines: bind group error, struct update parse error, std math absent, Gpa::default in tests, query-first hook friction).
