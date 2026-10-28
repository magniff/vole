# qwen35: Qwen3.5-0.8B on the GPU, in vole

Runs the text part of Qwen3.5-0.8B (the open weights in `model/`, a
symlink; read at run time, never copied) with every layer on the GPU:
bf16 weights in one storage buffer, WGSL compute kernels for the
matrix-vector products, RMSNorm, the causal conv1d, the gated delta-rule
recurrence, gated full attention with a KV cache, RoPE, SwiGLU and the
tied LM head. The tokenizer (byte-level BPE) and the chat template are
in vole too. Vision is not used.

## Build and run

```sh
volec main.vl -o qwen35          # about 3 s; std only, no C, no scripts
./qwen35 --headless --check      # the reference check (prints the speeds)
./qwen35 --headless --prompt "Write a haiku about a GPU." --tokens 60
./qwen35 --headless --prompt "..." --temp 0.7 --top-p 0.9 --seed 3 --shot chat.ppm
./qwen35                         # the chat window
./qwen35 --prompt "Hello"        # the window, with the message sent at once
```

- `--headless` prints the reply to stdout, streamed token by token; the
  speeds (prefill and decode, tokens a second) go to stderr. Without
  `--temp` it is greedy. `--raw` skips the chat template. `--shot FILE`
  also writes the chat as a PPM picture.
- `--headless --check` (`--check` alone works too) reads
  `reference/reference.json` at run time and compares: the token ids of
  the three prompts (plain, code, chat), the 24 greedy tokens of each,
  and the top-10 logits at each step.
- `--frames N` in window mode quits after N frames and prints the mean
  frame time.
- The model directory is the constant `DIR` in `main.vl`, an absolute
  path into this folder.

## The window

A chat: type a message, Enter sends it, the reply streams in token by
token (one decode step per frame), the header shows the tokens a second.
Backspace deletes; Escape (or closing the window) quits. The conversation
is kept (each message re-prefills the whole conversation, since the
model keeps no state between prompts). Sampling in the window is
temperature 0.7 with top-p 0.9 (`--temp`, `--top-p`, `--seed` change it).
Replies end at `<|im_end|>` or `<|endoftext|>`, or at 400 tokens.

The picture is drawn on the CPU (a 5 x 7 font, 1024 x 640 pixels, the
font table copied from examples/gpu/fluid2d) into a storage buffer, and
one fullscreen triangle shows it. Characters outside ASCII show as `?`.

## What was verified, and how

- `./qwen35 --headless --check`: all three prompts' token ids match
  reference.json exactly; the greedy continuations match for 24 of 24
  steps in each prompt (72 of 72 tokens); the top-10 logits agree with
  the reference's to 1e-4, which is the reference's own rounding (the
  maximum difference over every step and every top-10 entry is below
  0.0001). Output saved in `check-output.txt`.
- The residual stream after every layer, for the last token of the code
  prompt, matches the reference's `hidden_states` (rms and first 8
  values) to the printed precision: `./qwen35 --layers` (re-run on the
  final build).
- `volec test main.vl`: 7 tests pass at -O0 and -O2: the tokenizer on
  reference.json's tokenizer-only strings (ids and decode round trip),
  the chat markers, the digit split, the string table, the JSON number and
  escape readers, the nucleus sampler and the generator's repeatability.
- The headless `--shot` picture and the window path were run; the window
  itself could not be seen (the display was asleep: the harness reported
  "no frame in 3 s" and ran at 10 frames a second), so the window's
  picture was checked through the same drawing code, with `--shot`.

## Speed

Measured through `gpu-run` (`./qwen35 --headless --check`), decode about
51 to 67 tokens a second and prefill about the same per token: the
machine's load changed between runs (51 at load 18, 65 to 67 at load 2).
Prefill runs one token per step, as decode does (no batched prefill), so
its tokens a second equal decode's. One step reads about 1.5 GB of bf16
weights (the LM head is the tied embedding, read once per token).

## Limits

- Text only; one conversation at a time; context up to 2048 tokens.
- Chat template: the thinking-off form only (`<think></think>` empty),
  as the reference's prompts use.
- The pre-tokenizer is the Qwen regex written by hand: exact for ASCII and
  the reference's strings; non-ASCII letters are approximated by Unicode
  block ranges.
- The window draws one token per frame, so its streaming speed is capped
  by the display's refresh rate.
- `DIR` is an absolute path (the model is in this folder's `model/`).
