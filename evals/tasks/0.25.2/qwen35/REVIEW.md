> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric ([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2, re-ran the tests and every headless check through gpu-run, and read all the code. The orchestrator independently re-ran `--headless --check` on its own rebuild (PASS: greedy 24/24 on all three prompts, top-10 logits within 0.0001), ran a prompt not in the reference ("The three primary colors are" → a coherent answer naming red, green and blue; 58 tok/s decode), and checked the binary links only system frameworks (AppKit, QuartzCore, CoreGraphics, CoreFoundation, Foundation, libobjc, libSystem).

# Review: qwen35 (Qwen3.5-0.8B on the GPU)

## 1. Reproduction
Built and run from a copy of the sources in the orchestrator's scratch folder (`scratchpad/review/qwen35/`), with symlinks to `model/` and `reference/`. `volec test` writes a `.volec/` folder, so it was not run in the project folder.
- `volec main.vl -o …/qwen35`: `ok: built` (1.8 s).
- `volec test main.vl`: `5 passed (5 #[test]; -O0 and -O2 agree)`.
- `gpu-run --timeout 120 -- qwen35 --headless --check` (load 34–37):
  - for all 3 prompts, `ids match; greedy 24/24 steps match the reference; top-10 logits: largest difference 0.0001`;
  - `tokenizer: 3 reference strings, ids and decoding match`;
  - `check: PASS`;
  - 72 steps in 1.6–2.6 s.
- A copy that prints 6 decimals shows the real largest difference: 0.000056, 0.000056 and **0.000096**. That is at the 4-decimal rounding of reference.json (make_reference.py rounds to 4 places), so the agreement is essentially exact.
- Free generation:
  - `--prompt "The capital of France is" --tokens 24` gives the reference text (" Paris.\nThe capital…"). Prefill 11.9 tok/s, because the first call pays warm-up. Decode 45.1 tok/s.
  - `--chat` haiku: the reference haiku. Decode 40.5 tok/s.
  - A 200-token chat answer was coherent and stopped at `<|im_end|>`. Decode 48.6 tok/s at load 19.
  - `--temp 0.8 --top-p 0.9 --seed 7` produces fluent text.
- `--shot` rendered the chat with the haiku, the input line and a status line. Windowed mode was not run (no windows).

## 2. Claims vs reality
- **These hold:**
  - every `--check` line;
  - the 5 tests;
  - reproducing the free greedy text;
  - about 380 dispatches (I count 375);
  - context 2048;
  - the README's list of limits.
- **Speeds are plausible:** 40–49 tok/s for me under load 19–37, against the claimed 47–60.
- **"Near memory-bandwidth limits" is generous.** 1.5 GB per token (my count: 994 MB of layers plus 508 MB of LM head) at 60 tok/s is about 90 GB/s. That is about 60% of an M5's roughly 150 GB/s.
- **README overstates the window.** Its "Verified" section says the 120-frame window run "streams its reply and quits by itself". ANALYSIS admits that the final build's window run got no frames. README should carry the same caveat.

## 3. Task coverage
- safetensors reader: **done** (whole-file read, hand-scanned header).
- Byte-level BPE encode/decode with special tokens: **done**. \p{L}/\p{N} are approximated by ranges, and NFC is skipped; both are documented.
- WGSL forward pass, with bf16 read in the kernels: **done**. It covers matrix-vector products, RMSNorm (1+w), causal conv1d with state, the gated delta rule with carried state, GQA attention with a KV cache, partial RoPE, the output gate, SwiGLU and the chunked tied LM head.
- Greedy and temperature/top-p sampling: **done**. The sampler is not tested.
- Chat template: **done** for one turn. Multi-turn chat in the window is **partial** (see §4).
- `--check` reference ids, greedy continuation and logit closeness: **done**, and strong.
- Prefill and decode tok/s: **done**, but prefill runs one token at a time (admitted).
- Chat window, streaming, tok/s: **done in code**. The shot is verified; the final window run is not.
- Headless `--prompt --tokens`: **done**.

## 4. Correctness of the core
The kernels match the HF reference:
- **RMSNorm:** `inverseSqrt(mean+1e-6)` times (1+w) (`shaders.vl:83-89`).
- **Gated attention:** q and gate interleaved per head at a stride of 512 (`model.vl:270`, `shaders.vl:175`).
- **RoPE:** rotate-half on 64 dims, θ=1e7 (`shaders.vl:115-124`).
- **Attention scale:** 1/16.
- **Delta rule (`shaders.vl:230-257`):**
  - the L2 norm and the q scale 1/√128;
  - β=σ(b), with decay `exp(-exp(A_log)·softplus(a+dt_bias))`;
  - the S·decay, kv_mem, delta and outer-product update, one value column per thread, so there are no races;
  - the gated norm `w·norm(o)·silu(z)`.

Synchronisation relies on in-order dispatches in one compute pass (`model.vl:369-382`) and on `write_buffer`'s documented ordering against earlier submits. The exact match confirms both.

Issues:
- **Multi-turn bug:** `window.vl:173` ends a reply on `<|im_end|>` without feeding it to the model. The next turn's prefill therefore lacks the assistant's closing `<|im_end|>\n`, and the conversation's context diverges from the template.
- **Latent parser bug:** `weights.vl:88-128` treats any string after a key as the next key. A header with `"__metadata__":{"format":"pt"}` would turn "pt" into a tensor record and drop the next tensor. This file happens to have no metadata.
- **No logit tolerance:** the `--check` verdict (`check.vl:265-268`) ignores `pdiff`. A large logit error passes as long as every argmax agrees.
- **Performance:**
  - The attention softmax runs on one thread (`shaders.vl:159-169`).
  - Each u32 weight word is loaded by two threads in `mv`.
  - Fine at 2048 context, and decode is respectable.

## 5. Code quality
- **Structure:** a good nine-file split (weights, tokenizer, template, shaders, model, sample, check, window, font), with clear header comments. One prebuilt `Op` list per token is a nice design.
- **Idioms:** `inout self`, `sink` for `Chat::new`, `gpa` passed down. No `unsafe`.
- **Weak spots:**
  - Errors collapse to `Option`/`panic` (`Model::load` returns `None` for any failure; `make_pipe` panics).
  - Model dimensions are magic numbers in WGSL and in `model.vl` (2048u, 6144u, 16384u, 3584u) rather than coming from config.json.
  - Bytes are written as decimal codes (34, 58, 92) instead of `'"'`.
- **Duplication:**
  - `push_str`/`push_bytes` exist four times;
  - argmax three times (`model::argmax` is dead);
  - the JSON string-escape decoder twice (`check.vl:53`, `tokenizer.vl:518`);
  - `hex` and `hex_digit`.
- **Dead code:** `IM_START`, `THINK_START` and `THINK_END` are unused.
- **Inefficiency:** `reset` builds about 19 MB of zeros byte by byte on every call.
- **Hand-rolled math:** `exp_neg` (a Taylor series) for the sampler, as expected for 0.25.2.

## 6. Borrowing
- `font.vl`'s table is copied verbatim from `examples/gpu/fluid2d/font.vl`, and both README and the file say so.
- The window's full-screen-triangle text shader and the texture readback follow the guide's patterns.
- Everything about the LLM is original: the kernels, the tokenizer, the reader and the check. No example covers it.

## 7. Tests
- **The 5 `#[test]`s:** exp accuracy, decimal parsing, the GPT-2 byte table, and two pre-tokenizer split cases.
- **Untested:** BPE merging, both JSON/safetensors scanners, the top-p sampler and the template.
- **Covered end to end anyway:** `--check` is a strong integration test. Teacher-forced per-step argmax and top-10 logits catch any layer error, and the exact tokenizer ids include Unicode, emoji, tabs and special tokens.

## 8. Verdict
This is an impressive first program. A real 24-layer hybrid DeltaNet/attention LLM runs entirely in WGSL from vole. It matches transformers to the reference's own rounding over 72 teacher-forced steps, and it decodes at about 45–60 tok/s. The weak spots are mostly not in the model:
- token-at-a-time prefill;
- a window that was not re-verified on the final build;
- a multi-turn template slip;
- a fragile header scanner;
- duplicated helpers and magic numbers.

The report is accurate and self-critical, with small overstatements: bandwidth, and README's window claim.

**Grades:** result **A**, code **B**, honesty **A-**.
