# qwen35: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result
Works:
- `./qwen35 --headless --check` prints `fails 0`. Tokenizer on the reference's three texts (21, 5, 20 ids): ids and decoded text exact. Chat template: text and ids match the reference's chat prompt. Each prompt (plain, code, chat) over 24 greedy steps, teacher-forced with the reference's greedy tokens: greedy match 24/24 each, top-10 id set 24/24 each step, max |logit diff| vs reference top-10 = 0.0001 (the reference's 4-decimal rounding).
- Free-running `Write a haiku about a GPU.` gives the reference's text and stops at the end-of-turn token. `--raw` on "The capital of France is" continues as the reference does.
- `volec test main.vl`: 6 tests pass at -O0 and -O2.
- Speed (through gpu-run, GPU uncontended): decode about 60-70 tok/s; prefill about 80-90 tok/s (one token per submit, not batched).
- Temperature sampling: coherent, reproducible per seed (see status above).
- Chat window: type, Return, reply streams a token per frame, status line (tokens, tok/s, prefill tok/s), Backspace, Esc; multi-turn via caches.
Not verified:
- The window was not on the display during my runs (launched from a background shell: occluded, 10 frames/s timer). `--frames 150` ran to its limit, exit 0. Screen checked only via `--shot` (offscreen render, same layout and draw code, PNG viewed). Live keyboard and streaming not seen.
- Prefill is sequential. The pre-tokenizer approximates the regex's Unicode classes by code-point ranges. NFC not applied. Chat KV cache holds 2048 positions.
Commands: `./qwen35 --headless --check`; `./qwen35 --headless --prompt "Write a haiku about a GPU." --tokens 80`; `... --tokens 60 --shot shot1.ppm` then tools/ppm2png.py; `volec test main.vl`; `./qwen35 --frames 150 --prompt "..." --tokens 40` (windowed, via gpu-run).

## 2. How you worked
- volec guide (gpu, std, syntax, types, text, allocators, window, cli, testing, math, --find): about 15 calls. The gpu topic's examples were the most useful.
- volec query items/show: about 10 calls. A `query show` on a struct gave the fields faster than the guide.
- volec check after edits via the hook: about 50 runs; plus about 20 builds and 2 volec test. The hook's per-error line and `try:` lines were what I used most. The hook applied `&` markers to my call sites itself. `volec fmt main.vl` cleared the "not formatted" note.
- I did not use volec edit, refactor, or query context: I wrote files whole. I should have used query context on the std handles I depended on.
- The query-first hook blocked one shell grep of compiler/std; I re-ran via volec query.
- Mistake: `sed -i` without '' on macOS, one wasted turn.
- gpu-run waited 197 s once for other agents' GPU programs; one windowed run hit its 60 s timeout while the window was not shown.
- Two tools/agent-feedback lines recorded (gpu handles not Copy; str and [u8] constant forms).

## 3. What went well
- The gpu API covered everything: compute passes, bind groups, write_buffer, copy_texture_to_buffer, render pass, map_read. No C, no extra modules.
- gpu `requires` messages are specific. None fired at run time.
- check gives one line per error with a try: line; conv.marker fixes applied automatically.
- std::fs::read_in read the 1.7 GB checkpoint in ~0.6 s; buffer_init takes the bytes straight from the file slice.
- volec test with -O0/-O2 agreement is cheap. std::cli parse_or_exit with get_as::<T> is short.
- Checked indexing: no out-of-bounds bug reached me.
- The first real GPU run matched the reference (after one gate-formula fix found by reading before running).

## 4. What went badly
1. `expected 'Vec<u8>', got '[u8]'` for `ms[k].key == key`. Fix: `.as_slice()`.
2. `unknown type 'IoError'`: the alias from std's signatures is not in user scope; `std::io::Error` works.
3. `cannot infer type parameter 'E' of 'Result'` on an Ok(...) return: fixed by the return type.
4. `an f-string is a 'std::Interp' ... not '[u8]'`: use format_in(f"...", gpa). panic takes [u8]; the guide does not say so.
5. `constant 'X' has type 'str'; constants must be integers, floats, bool or string literals` for `const X: str`. `const X: [u8] = "..."` is accepted. `const X: [str] = [...]` is refused; `static X: str` works. Three attempts.
6. `distinct.mix 'MODEL_DIR' is '[u8]' where 'str' goes`: the guide says a str goes where [u8] does, not the reverse.
7. `own.moved 'dev' is used here after it moved` when a gpu::Device goes into a struct literal. Device and Buffer are not Copy; struct fields and Vec::push move them. Fix: pass dev as a let parameter. Worst time sink: four attempts.
8. `own.moved 'cstate' ... moved into 'Vec::push(sink x)'`: same cause.
9. `own.move_out cannot move 'xs' (Vec<Json>) out of a reference`: a match on a let access cannot move the Vec. Fix: as_slice().
10. `arithmetic operator requires numeric type, got 'Duration'`: use saturating_sub.
11. My own edit errors (`no method 'as_slice' on type '[u8]'`, `expected ';', got ')'`, and an undefined variable after a silently missed str.replace). Re-check caught them.
12. `conv.marker 'net' is lent inout here ... mark it '&net'`: many; the hook fixed most.
13. `no associated function 'new_in' in 'Gpa'` in a test: a #[test] takes gpa as a parameter.
14. `'[i64]' does not implement Display` / `Debug` for `{x}` and `{x:?}` on a slice; no reason given.
15. `unknown module 'font'` when checking ui.vl alone: correct, but confusing; check from main.vl.
Guide or docs missing: which gpu handles are Copy and which move, and how to keep them in structs or Vecs (most important); string constant forms and conversions; headless offscreen render to a texture and readback; window timer frames when not displayed.
Time sinks: model constructor about 25 checks; tokenizer 3 checks; window about 3 runs (GPU lock 197 s, occluded window).

## 5. The language
Fought me: ownership of GPU handles; the string and slice split ([u8], str, Vec<u8>, Buf, String, f-string) with as_slice/as_bytes/format_in/extend_from_slice in different places; const vs static for strings and arrays; inout and let parameters needing & on pass-through calls, and closure captures in compute_pass; match on a let access moves nothing.
Liked: enums with payloads and match (the JSON reader); #[test] next to the code with -O0/-O2 agreement; std::cli; Result with ? on gpu calls; checked indexing; gpu requires messages that name the binding and the fix.

## 6. Suggestions, ranked by time saved
1. Document which gpu handles are Copy and which move, and how to store a Device/Buffer in a struct or Vec. Four attempts for me.
2. A str/[u8] table in the guide: allowed constant forms, what each conversion does, and that panic takes [u8]. About 6 attempts.
3. Suggestions for Vec vs slice comparison ("use .as_slice()") and for Duration arithmetic (saturating_sub).
4. Make {x:?} work for slices of numbers, or say why not.
5. A volec query answer for "is this type Copy, does it move".
6. A window guide line: a window not on the display gets 10 frames/s; what --frames tests look like from a background shell.
7. Say in the key example that Return and Tab arrive as Key events and may also carry a control-character Text.
8. A checked offscreen-render-to-file example next to the window example.
