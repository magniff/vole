> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: qwen35 (Qwen3.5-0.8B on the GPU)

## 1. Reproduce
I built from a scratch copy of the .vl files, with `model` and `reference` symlinked: `volec main.vl -o qwen35` printed `ok: built qwen35`. `volec test main.vl` gave `7 passed (-O0 and -O2 agree)`, and `volec check` reported 0 errors.
- `gpu-run --timeout 120 -- ./qwen35 --headless --check` (load 11) exited 0. Each of plain, code and chat printed `ids match; greedy 24/24 match; top-10 logits within 0.0001`. Decode ran at 65.0, 66.5 and 65.4 tok/s, and prefill at 23 to 66 tok/s.
- `--headless --prompt "Explain what a GPU is in one sentence." --tokens 40 --temp 0.7 --top-p 0.9 --seed 3` gave a coherent sentence at 64.8 tok/s.
- I did not open the window.

## 2. Claims vs reality
The core claims hold exactly: ids match, 72 of 72 greedy tokens match, logits agree to about 1e-4, and decode runs at 51 to 67 tok/s. Overstatements:
- "below 0.0001": the value is printed with `{worst:.4}` (check.vl:186), so 0.0001 means anything up to about 1.5e-4. "About 1e-4" is what is shown.
- README: "Sampling in the window is temperature 0.7 with top-p 0.9". This is false. The options have `.default("0")` and `.default("1")` (main.vl:109-110), and std::cli's `get` returns the default, so `unwrap_or("0.7")` at main.vl:141-142 never fires. The window samples greedily. I confirmed `get` returns the default with a 6-line probe.
- The logit tolerance is reported but not checked: only ids and the greedy count decide the exit status (check.vl:182).

The report is candid about its own bugs (`read_ints` off-by-one, state not reset), about prefill not being batched, and about the window not being seen.

## 3. Task coverage
- safetensors reader: done (its own JSON parser).
- BPE tokenizer, encode and decode: done. Non-ASCII letter classes are approximated by Unicode blocks (tok.vl:61-86).
- WGSL forward pass with bf16 read in the kernels, matvec, RMSNorm, conv1d with state, the gated delta rule with state, attention with a KV cache, partial RoPE, SwiGLU and the tied LM head: done.
- Greedy and temperature/top-p sampling: done (top-p over the top 64 tokens).
- Chat template: done (thinking-off form only).
- `--check` ids, greedy and logits: done.
- Prefill and decode tok/s: done; prefill is unbatched.
- Chat window: done but unverified. It is ASCII only and greedy (bug above).
- `--prompt/--tokens`: done.

## 4. Correctness of the core
The kernels are right. The delta rule (kern.vl:128-165) l2-normalises q and k, scales q by 1/sqrt(128), decays the state by exp(-exp(A_log)·softplus(a+dt_bias)), then does the delta update and the readout. Partial RoPE rotates pairs (i, i+32) over 64 dims with theta 1e7 (kern.vl:195-209, model.vl:290-293). Gated attention multiplies the output by sigmoid(gate) (kern.vl:272). Norms use 1+w (model.vl:134-141). All dispatches are in one compute pass (model.vl:426-432). The `--check` is a strong end-to-end test.

Weaknesses:
- The LM head (248k×1024, about 0.5 GB of bf16) runs for every prefill token, because the op list is fixed (model.vl:415). That is why prefill is no faster than decode.
- The whole 1.75 GB file is read into RAM and uploaded, header included (model.vl:225, 305).
- Absolute paths are hard-coded (main.vl:21, check.vl:112, tests.vl:8).
- When the chat context is full, `send` clears the typed input and returns without replying (chat.vl:91-97).
- The 8-thread serial softmax (kern.vl:241-255) is fine at 2048 positions.

## 5. Code quality
The split into 11 modules (st, tok, kern, model, check, gen, chat, canvas, font, tests) is sensible, and the comments are good. There is no `unsafe`. Issues:
- The tensor-name building in model.vl:332-410 repeats `name.clear(); push_str(pre); push_str(...)` about 20 times; a `tname(l, suffix)` helper would halve it.
- Token and position are stored in the f32 buffer as bit-cast words. It is a hack, but it is documented.
- It reinvents std pieces: UTF-8 decode and encode (tok.vl:33-58, st.vl:96) where std::str has `decode_at`, `utf8_char_width` and `encode_utf8`; xorshift (gen.vl:7-25) where std::random exists; and its own StrMap where `HashMap<[u8], i64>` is in the prelude.
- Float math uses std (`powf`, `exp`).

## 6. Borrowing
Only the 5×7 font table comes from fluid2d (font.vl, and the README says so). The model, tokenizer and kernels are original.

## 6b. New features
None of the 0.25.2.1 features apply to this task. It raises `Limits.max_buffer_size` correctly (model.vl:302-304).

## 6c. Compiler bug
Not hit: each shader is bound to a `let` (model.vl:319-320).

## 7. Tests
The 7 tests cover the tokenizer against all three of reference.json's tokenizer-only strings, with a decode round trip (strong), plus the JSON readers, StrMap, the sampler and the RNG. Gaps:
- No test of safetensors header parsing.
- `--layers` prints values but compares against nothing, and reference.json's `hidden_last_position` for "plain" goes unused.
- The window input and drawing paths are not exercised.

## 8. Verdict
A real 0.8B hybrid DeltaNet/attention LLM runs entirely in vole WGSL, token-exact against transformers, at about 65 tok/s. This is an outstanding result for 24 minutes. The code is clear but repetitive in places, reinvents some std pieces, and hard-codes paths. The report is accurate and self-critical. The one false claim (window sampling) is a real bug the agent did not notice, and the logit precision is stated a little too strongly.

**Grades:** result **A**, code **B+**, honesty **A-**.
