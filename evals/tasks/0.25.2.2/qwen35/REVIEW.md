> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.

# Review: qwen35 (Qwen3.5-0.8B on the GPU)

## 1. Reproduce
I copied the `.vl` files to a scratch directory and symlinked `model` and `reference` into it.
- `volec main.vl -o qwen35` → `ok: built qwen35`. `volec test main.vl` → `6 passed (-O0 and -O2 agree)`.
- `gpu-run --timeout 120 -- ./qwen35 --headless --check` (2.96 s wall): `tokenizer true` ×3 (21, 5, 20 ids), `prompt plain/code/chat true: greedy 24/24 top10 24/24 max |logit diff| 0.0001 first miss -1`, `chat template: the text and ids match`, `fails 0`. This is the same as the orchestrator's rerun.
- `--headless --prompt "Write a haiku about a GPU." --tokens 40` gives the reference haiku, stops at end-of-turn, and prints `prefill 82.2 tok/s; decode 16 tokens`. The whole process took 0.97 s.

## 2. Claims vs reality
The check numbers, the haiku and the test count all hold. One overstatement: "decode about 60–70 tok/s" is not something the headless mode prints. `main.vl:82` prints the prefill rate and the decode *count* only. The decode rate appears only in the window's status line and in the `--shot` picture. The 0.0001 logit difference is real, but it is printed, not judged (see 4). The README is clear that the check is teacher-forced and lists its limits honestly: sequential prefill, approximate pre-tokenizer classes, no NFC, a 2048-position cache.

## 3. Task coverage
- safetensors reader: done (`st.vl`).
- BPE encode and decode: done. The Unicode classes are approximated, as the report says.
- Forward pass in WGSL: done. bf16 is read in the kernels; there are matvec, zero-centred RMSNorm, conv1d with state, the gated delta rule with carried state, partial RoPE (theta 1e7), GQA attention with a KV cache and the output gate, SwiGLU, and the tied LM head.
- Greedy and temperature/top-p sampling, and the chat template: done.
- `--check`: done.
- Tokens per second: partial. Headless shows prefill only; decode is shown in the window.
- Chat window with streaming and tok/s: done, but only checked through `--shot`.
- `--prompt/--tokens`: done.
- `config.json` is never read. Every dimension and the layer pattern (`(l+1)%4`) are hard-coded constants (`model.vl:13-37`).

## 4. Correctness of the core
The kernels in `wgsl.vl` match the reference:
- l2-normalised q and k with eps 1e-6, and q scaled by 1/√128 (`wgsl.vl:157`).
- decay `exp(-exp(A_log)·softplus(a+dt_bias))` (163).
- The delta update S·decay, then `(v − Sᵀk)·β`, then `S += k⊗δ`, then `o = Sᵀq` (166-171). Each thread owns one column, so there are no races.
- Gated RMSNorm × silu(z) (174).
- RoPE with ln(1e7) = 16.118 over pairs (i, i+32) (187-190).
- Attention scaled by 1/16 with kv head h/4, and the gate read from the interleaved q/gate layout (226-243).

The structure is good: the dispatches are prebuilt as an `Op` list, and each token is one compute pass and one submit (`model.vl:279-294`), as the guide recommends. Dtypes are hard-coded per tensor. They are right for this checkpoint (A_log and the linear-attention norm are F32, dt_bias is BF16), but `SafeTensors::is_f32` and `shape` are parsed and never used (`st.vl:107`). A single prompt longer than about 1984 tokens would overrun the cache: `submit` resets but does not truncate (`chat.vl:54`).

**The check (`check.vl`).** It is teacher-forced: it feeds `greedy[k]` (`check.vl:164-166`). Because argmax matched at all 24 steps, free-running greedy decoding would produce the same tokens, so teacher forcing hides nothing here. Its strengths are that the top-10 ids are compared in order and that logits are compared on the reference's own ids. What it misses:
- (a) `maxd` is not part of pass/fail (`check.vl:168`). A drift or rescaling of the logits that keeps the top-10 order would still pass.
- (b) Positions reach only about 43 (prompts of at most 20 ids plus 24 steps). RoPE at large positions, long-context softmax, the 2048-entry workgroup score array and the context-full path are untested.
- (c) The multi-turn state carry, where the chat appends turns without a reset, is untested; the check resets between prompts.
- (d) Sampling is untested.
- (e) `hidden_last_position` is unused. It would locate a failing layer, but only matters when something fails.

## 5. Code quality
The module split is sensible (json, st, tok, wgsl, model, run, chat, ui, app, check). There is no `unsafe`. The WGSL is generated with long `push_str` chains that bake in constants (`wgsl.vl`), which are hard to read and review. The `bf()` helper is duplicated across modules. The handle ownership the report fought with ended up clean: the `Builder` owns its Vecs. Good details: `gen_one` scopes the mapped logits view in a block before `net.step` (`chat.vl:72-75`), and HiDPI is handled through `screen.fit(.., scale)`. No hand-rolled math was found.

## 6. Borrowing
The 5×7 font data is from `fluid2d/font.vl` (33 shared lines, credited in the README). Everything else is original.

## 6b. New in 0.25.2.2
There are no uniforms at all: per-token parameters go in a STORAGE buffer `pb`, so `gpu.unwritten` could not fire. The program uses one module per kernel shape, with no use of shared modules, storage formats, integer methods or `adapter.limits()`. The 65535 dispatch limit is handled by hand for the LM head (`model.vl:64`, `dx` = 65535).

## 6c. Mapped views
`logits_of` returns a live view (`run.vl:149-151`). In `check.vl:138-165` the view `lg` is read only before that iteration's `m.step`, and `gen_one` drops it explicitly. No result depends on the soundness bug.

## 7. Tests
There are 6 unit tests: JSON, the byte map, pre-tokens, the template, UTF-8 splitting, and argmax/topk. Together with the reference check, the tokenizer and the logits are well covered. The gaps are the ones in 4: long contexts, multi-turn, sampling, and a logit tolerance.

## 8. Verdict
This is a real LLM, a hybrid DeltaNet/attention model, running correctly on the GPU from a young language. It matches transformers to about 1e-4, runs at about 65 tok/s decode, and has a working chat UI, written in about 25 minutes. The weak spots are that config is hard-coded, the headless decode rate is not printed, and the check prints the logit error without judging it. The report is candid and specific.

**Grades:** result **A**, code **B+**, honesty **A-**.
