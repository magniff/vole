# qwen35: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file ("Subagents should return findings as text"). Nothing is edited but this note and the headings' markup.

qwen35: Qwen3.5-0.8B (text only) runs on the GPU from vole and matches the transformers CPU reference. Project folder: /Users/magniff/workspace/tachyon/evals/tasks/0.25.2/qwen35/ (builds with `volec main.vl -o qwen35`; README.md is there; the screenshot is shot.png).

FILES (all in the folder): main.vl (CLI), tokenizer.vl (byte-level BPE + Qwen pre-tokenizer + specials), weights.vl (safetensors reader), shaders.vl (WGSL, one module per kernel), model.vl (GPU buffers, ~380 prebuilt dispatches per token), sample.vl (greedy, temperature, top-p), check.vl (--check), template.vl (chat turn), window.vl (chat window + --shot picture), font.vl (font table copied from examples/gpu/fluid2d/font.vl; the README says so), README.md.

## 1. Result

Works. Final build, `./qwen35 --headless --check` (run through gpu-run):

```
prompt 0: 5 tokens, ids match; greedy 24/24 steps match; top-10 logits largest difference 0.0001
prompt 1: 6 tokens, ids match; greedy 24/24 match; 0.0001
prompt 2: 20 tokens (chat), ids match; greedy 24/24 match; 0.0001
tokenizer: 3 reference strings, ids and decoding match
check: PASS
```

The check runs each prompt with teacher forcing (the reference's greedy tokens fed back), so each of the 72 steps is compared with the reference's top-10 distribution. Free greedy generation gives the reference continuations (" Paris.\nThe capital of France is Paris..." and the haiku). 128- and 200-token runs complete. Sampling (`--temp 0.8 --top-p 0.9 --seed 7`) runs; there is no reference for it.

`volec test main.vl`: 5 tests pass at -O0 and -O2.

Window: the 120-frame test run (`--frames 120 --say Hi`) streamed a reply and quit by itself on earlier builds. The final build's window test did not get frames (see 4.5), so the last window evidence is from the earlier build. The headless `--shot` renders one chat frame into a texture; I checked the PNG by eye: transcript, input line with cursor, and the status line with prefill and decode tok/s are in place.

Speed (gpu-run; machine load 13 to 20 from other agents, so numbers move): decode 47 to 60 tokens/s (about 16 to 21 ms a token); prefill 50 to 57 tokens/s (prompt tokens run one at a time). Decode reads about 1.5 GB of bf16 weights per token, so it is near memory-bandwidth limits.

Not done: batched prefill; vision tower and MTP head (text only, per the brief).

Approximations (in the README): \p{L}/\p{N} by Unicode ranges (exact for ASCII and common scripts); no NFC normalization; the 26 added tokens and the chat template are written in the program; context limit 2048 positions.

## 2. How I worked

- volec guide (core primer), guide gpu, guide window, guide --find: about 6 lookups; the core and gpu sections were enough.
- volec query: about 12 calls (items, show, grep). Little use of context or refs.
- volec check: about 25 runs; the hook's "fixed" notes (volec fix --suggested: &mut to &, unused imports) saved edits.
- volec main.vl -o: about 20 builds, 1 to 2 s each. volec test: 5 runs. volec fix --only unused: worked.
- volec edit patch: 4 tries; it refused edits that left one error between edits (edit.breaks) unless --no-check. I switched to the Edit tool (replace_all was good for renames), and to heredoc rewrites (cat > file <<'EOF') for whole-file changes.
- query-first hook: blocked shell reads of .vl about 8 times, even for a 39-line file, and blocked python and sed -i writes to .vl.
- gpu-run: about 15 runs.

## 3. What went well

- The language is pleasant once it compiles: for/while/loop/match, Option/Result, f"..." printing, Vec::new_in(gpa), explicit allocators with clear errors.
- #[test] with gpa: Gpa; tests agree at -O0 and -O2.
- std::gpu: one encoder, one compute pass with about 380 dispatches, bind groups built once, uniform buffers for params, map_read for logits. buffer_init and f32s (zero-copy views of bytes) made bf16 simple: matrices go to storage buffers as they are; the kernel reads two bf16 per u32.
- Ownership errors (own.move_out, own.moved, conv.marker) name the variable and the fix.
- std::window Event::Text, Key and Named::Enter: easy text input.
- The tokenizer matched the reference ids on the first build for the first prompt.

## 4. What went badly (ranked by time)

1. query-first hook (about a quarter of my turns). Shell reads of small .vl files are blocked; a blocked command drops the whole Bash call. My `cat > a && cat > b && ...` chain silently created nothing. Message: "PreToolUse:Bash hook error: ... blocked hook.query-first: head -8 font.vl (command 6 of 7 on the line; the others are not blocked)" — the others were not run either.
2. WGSL is checked only at run time, per module. One module with several entry points each using @group(0) @binding(0) passed volec check and failed at run time: "shader did not compile: 38:36: error wgsl.binding: @group(0) @binding(0) is also 'mvp'". The fix (one module per kernel) is not in the gpu guide.
3. ComputePipeline is neither Copy nor Clone. Storing one in a struct gave "own.move_out: cannot move 'pipe' ... copy it ('.clone()')", but there is no clone: "no method 'clone' on type 'ComputePipeline'". Fix used: store an index into a Vec.
4. Device (holds a Gpa) is owned. `let dev = chat.model.dev;` moved out of a field, and later uses failed ("'chat' is used here after 'chat.model.dev' moved"). About 15 uses became chat.model.dev.
5. Window test hang: `./qwen35 --frames 120 --say Hi` ran for minutes with no Frame events in App::wait_timeout (sampled: vole.std.window.App.wait_timeout -> NSApplication nextEventMatchingMask). The same code had produced frames earlier. My guess: the window was occluded by other agents' windows (macOS sends no frame events to a hidden window); not confirmed. App::wait() blocks forever in this state. I switched test runs to wait_timeout(250) with a re-request; the final run was not completed.
6. My own bugs: (a) prompts 2 and 3 of the check were off by up to 6.4 in the logit: linear-attention and conv states carried over from the previous prompt; fixed with Model.reset() (about 3 builds). (b) The tokenizer check seeked both "text" and "ids" before reading the text, so it parsed an array as a string and eventually ran out of memory (exit 137); found with a dbg print (about 4 runs).
7. No safe exp/ln in std (only libm externs needing unsafe). The top-p sampler needed exp; I wrote a Taylor series with range reduction (test: accurate to 1e-8).
8. No multi-line string literals: "newline in string literal". WGSL needs a `\n\` continuation on every line (shader is about 280 lines).
9. Smaller: an f-string passed to a [u8] parameter ("an f-string is a 'std::Interp' ... not '[u8]'") needs format_in (hit 3 times); Vec<u8> has no push_str while Buf does; Duration has no duration_since (saturating_sub works); no Limits field for storage binding size (I chunked the 508 MB embedding into 32768-row buffers without testing the default); edit patch's edit.breaks refusal; a Result<_, IoError> hint pointed at an import instead of the real problem.

## 5. The language

Fought me: owned handles in structs (4.3, 4.4); the let-parameter rule ("cannot store") is learned from errors, not the guide; passing Vec or Buf to a [u8] parameter needs .as_slice(); i64 everywhere with casts from u8 (`(s[k] - 48) as i64`); no raw strings.

Liked: #[test] and volec test; Result/Option with match and ?; std::gpu's object model and map_read; std::fs::read_in for the 1.7 GB file; the help: lines on errors (conv.rust, own.*).

## 6. Suggestions, ranked by time saved

1. Let query-first allow head/tail/sed -n on small .vl files, and stop dropping the whole Bash call when one command is blocked. About a quarter of my turns.
2. Check WGSL in volec check (or at shader_wgsl for string constants): bindings, types, entry names.
3. Document the one-module-per-kernel rule in guide gpu, and why.
4. Fix the own.move_out help: ".clone()" does not exist for handles; say "store an index" or take the value by sink.
5. Raw or multi-line string literals; every GPU program carries WGSL.
6. exp, ln, sqrt, pow for f32 and f64 in std, safe, not libm externs.
7. A window test mode that cannot hang: wait with a timeout, or a timer Frame when no frames arrive.
8. A batched-prefill example in the gpu guide (matrix-matrix kernel).
9. String helpers on Vec<u8> (push_str, push_fmt).
10. edit patch: accept a batch whose end state is clean, instead of refusing intermediate states.

Counts: about 20 builds, about 25 volec check runs, 5 volec test runs, about 15 gpu-run runs. Turns lost: about 5 to my own bugs, 3 to the WGSL binding error, 4 to pipeline and device moves, about 10 to the query-first hook.

Tool feedback recorded with tools/agent-feedback (8 lines): query-first hook; WGSL bindings per module; ComputePipeline clone hint; gpu Device field move; std math exp; window wait hang; edit patch edit.breaks; multi-line string literals.
