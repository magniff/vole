# qwen35: Qwen3.5-0.8B on the GPU, in vole

Qwen3.5-0.8B (text only; the vision tower is ignored) runs from vole on the
GPU through std::gpu. The checkpoint is read at run time from `model/` (a
symlink to `/Users/magniff/models/Qwen3.5-0.8B`), bf16 weights uploaded as
they are and read by the kernels. Nothing is copied or converted on disk.

Build (from this folder): `volec main.vl -o qwen35`

## Run

    ./qwen35                                   # the chat window
    ./qwen35 --headless --check                # against reference/reference.json
    ./qwen35 --headless --prompt "Write a haiku about a GPU." --tokens 80
    ./qwen35 --headless --prompt TEXT --raw    # plain text, no chat template
    ./qwen35 --headless --prompt TEXT --temp 0.8 --top-p 0.9 --seed 7
    ./qwen35 --headless --prompt TEXT --shot shot.ppm   # the chat screen as a PPM
    ./qwen35 --frames 150 --prompt TEXT        # window, quits after 150 frames (a test)

Headless prints the reply on stdout and the speeds on stderr
(`prefill N tok/s; decode M tokens`). Run GPU programs through
`evals/tasks/0.25.2.2/tools/gpu-run` (the GPU lock).

## Controls (the window)

- Type a message (the text field is the bottom line, with a cursor).
- Return sends it; the reply streams in a token per frame.
- Backspace deletes the last character of the input.
- Esc quits.
- The status line shows the tokens of the reply, their rate, and the prefill rate.

The conversation keeps its state in the GPU caches: a new turn feeds only its
own tokens. A conversation holds 2048 positions; when it is full the next turn
starts a new conversation (the screen says so).

## What it is

- `main.vl`: the command line (std::cli), headless and check modes, the window.
- `json.vl`: a small JSON reader (config, safetensors headers, reference.json).
- `st.vl`: the safetensors file, read whole; tensors are read in place.
- `tok.vl`: byte-level BPE from `vocab.json` and `merges.txt`: encode (pre-tokens,
  merges by rank, special tokens recognised) and decode.
- `wgsl.vl`: the WGSL kernels, one module per kernel shape: bf16 matrix-vector
  products (one workgroup per row), zero-centred RMSNorm, the embedding gather,
  the causal conv1d with its state, the gated delta rule (one workgroup per head,
  one thread per state column, state in storage), partial RoPE, the KV store,
  causal GQA attention with the output gate, SiLU-gated MLP product.
- `model.vl`: the weights uploaded, the pipelines and bind groups built once,
  and one compute pass per token (24 layers; the head only when the logits are wanted).
- `run.vl`: the chat template, sampling (greedy, or temperature with top-p over the
  256 likeliest tokens), the RNG, feeding tokens.
- `chat.vl`: the chat state: a turn, the reply one token at a time, the status line.
- `ui.vl`, `font.vl`: the chat screen: a character grid drawn by one full-screen
  pass, a 5 x 7 bitmap font (ASCII; other bytes show as `?`).
- `app.vl`: the window loop (one token per Frame event) and the offscreen shot.
- `check.vl`: the `--check` comparison.

The forward pass follows `reference/modeling_qwen3_5.py`: the gated DeltaNet
layers (conv state, l2-normalised q and k, query scaled by 1/sqrt(128), decay
`exp(-exp(A_log) * softplus(a + dt_bias))`, beta `sigmoid(b)`, the delta-rule
update, the gated RMSNorm with silu(z)), the gated full-attention layers (q and
gate interleaved per head, GQA 8 over 2, head dim 256, partial RoPE on 64 dims,
theta 1e7, output times sigmoid(gate)), zero-centred RMSNorm `x * (1 + w)`,
SwiGLU, tied embeddings.

## What was verified, and how

Commands, from this folder (all run through gpu-run):

1. `./qwen35 --headless --check`: all four checks pass.
   - Tokenizer on the reference's three texts (21, 5, 20 ids): ids and decoded
     text match exactly, including the Chinese, emoji and quote text.
   - The chat template: the rendered text and its ids match the reference's
     `chat` prompt exactly.
   - Each prompt (`plain`, `code`, `chat`): the 24 greedy steps are compared
     with the reference, feeding the reference's own greedy tokens (teacher
     forcing). Greedy token matches 24/24 for each prompt, the top-10 token ids
     match 24/24 at each step, and the largest difference between our logit and
     the reference's logit (for the reference's top-10 ids) is 0.0001. The
     reference stores logits rounded to 4 decimals, so this is at the rounding
     floor.
   - Output: `fails 0`.
2. Free-running headless generation: `Write a haiku about a GPU.` gives
   `Silicon gleams, / Cooling vents hum, / Code runs bright.` and stops at the
   end-of-turn token, the same text as the reference's greedy continuation.
3. `./qwen35 --headless --raw --prompt "The capital of France is"` continues
   with the reference's text (` Paris.\nThe capital of France is Paris...`).
4. `volec test main.vl`: 6 unit tests (JSON, byte-level mapping, pre-tokenisation,
   the chat template, UTF-8 splitting, argmax and top-k), passing at -O0 and -O2.
5. The screen: `--shot` renders the chat (1280 x 720) offscreen; the PNG was
   looked at (`shot1.png`): the transcript, the input line with cursor and the status line.
6. Windowed: `./qwen35 --frames 150 --prompt ...` ran to its frame limit and exited 0.
   The window was not on the display during the run (it was launched from a
   background shell), so the on-screen result was checked with `--shot` only.

Speed (through gpu-run, on this Mac):

- decode: about 60 to 70 tokens per second (16 to 40 token runs, short and long context);
- prefill: about 80 to 90 tokens per second; the prompt is fed one token at a time.

## Limits

- The pre-tokeniser approximates the Unicode classes of the model's regex
  (letters, marks, numbers, spaces, symbols) by code-point ranges. It is exact for
  ASCII, Latin, Greek, Cyrillic, CJK, kana, Hangul and emoji, and approximate elsewhere.
- NFC normalisation (the tokenizer's normaliser) is not applied; the text is taken as typed.
- The special tokens of the chat format (`<|im_start|>`, `<|im_end|>`, `<think>`,
  `</think>`, `<|endoftext|>`) are recognised in the text; other special tokens
  are not.
- Prefill runs one token per submit, so prompt processing is far slower than a
  batched matrix-matrix pass would be.
- The KV cache holds 2048 positions per conversation.
- The screen shows printable ASCII only; other characters appear as `?`.
- The font table in `font.vl` is the 5 x 7 table of `examples/gpu/fluid2d/font.vl`
  (its data, not its code).

The analysis of building this, with the errors met, is in `ANALYSIS.md`.
