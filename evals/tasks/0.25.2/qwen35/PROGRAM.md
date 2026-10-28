# qwen35: Qwen3.5-0.8B on the GPU, in vole

Runs the text model of Qwen3.5-0.8B (24 layers: 18 Gated DeltaNet linear
attention, 6 gated full attention; RMSNorm, SwiGLU, tied embeddings, vocab
248,320) from vole. The weights are read at run time from `model/` (a symlink
to the model folder; the bf16 safetensors file is read, never copied). The
forward pass is WGSL compute kernels run through `std::gpu` (Metal).

## Build and run

```sh
volec main.vl -o qwen35          # in this folder; std only, no helper files
./qwen35                         # the chat window (std::window)
./qwen35 --headless --check      # the reference check (see below)
./qwen35 --headless --prompt "The capital of France is" --tokens 24
./qwen35 --headless --chat --prompt "Write a haiku about a GPU." --tokens 60
./qwen35 --headless --prompt "Once upon a time" --tokens 40 --temp 0.8 --top-p 0.9 --seed 7
./qwen35 --headless --shot shot.ppm --say "Write a haiku about a GPU."   # the window's picture
./qwen35 --frames 120 --say "Hi"  # the window, quits by itself after 120 frames (a test)
volec test main.vl               # the #[test] functions (-O0 and -O2)
```

Headless runs print the text on stdout and the speeds on stderr:
`prefill: N tokens ... tokens/s` and `decode: N tokens ... tokens/s`.
Without `--temp` (or with 0) decoding is greedy.

## The chat window

Type a message; Return sends it (it is wrapped in the chat template and
its prompt is prefilled), and the reply streams in one token per frame. The
status line shows the prefill and decode speeds in tokens per second and
the context position. Backspace deletes; Escape quits. The conversation
keeps its KV cache and states, so follow-up messages continue it; when the
2048-position context is full, the conversation starts again.

The screen shows a grid of characters drawn by a full-screen shader from a
5 x 7 font (the font table is the one of `examples/gpu/fluid2d/font.vl`).

## What it does

- `weights.vl`: reads the safetensors file (the header is scanned for each
  tensor's dtype and byte range). bf16 matrices go to the GPU as they are; the
  small tensors (norms, conv weights, dt bias) are widened to f32 on load.
- `tokenizer.vl`: byte-level BPE from `vocab.json` and `merges.txt` (ids
  and merges, the vocabulary in an open-addressing hash table, the merges as
  pair-to-rank table); the Qwen pre-tokenizer regex written out by hand over
  code points; the added tokens matched before pre-tokenizing; decoding.
- `template.vl`: the chat template for one user turn with the generation
  prompt (an empty think block), as `chat_template.jinja` renders it.
- `shaders.vl`: the WGSL kernels, one module each: `mv` (bf16 matrix-vector,
  a workgroup per row), `norm` (RMSNorm with the (1 + w) weight, per head or
  whole vector), `rope` (partial RoPE on 64 of 256 dims, writes q, and k and v
  into the KV cache), `attn` (causal attention over the cache, GQA 8 over 2,
  output gated by sigmoid), `conv` (causal depthwise conv1d, kernel 4, its
  state, SiLU), `delta` (L2-normed q and k, decay and beta, the per-head
  state update, the gated RMSNorm with z), `addv`, `swiglu`.
- `model.vl`: buffers, pipelines, and the dispatches of one token: about 380
  dispatches with one bind group each, built once; one compute pass per
  token. The embedding row is widened on the CPU and written to the residual
  buffer; the position goes in a small buffer the kernels read. The LM head is
  the tied embedding, in chunks of 32768 rows (a binding size limit).
- `sample.vl`: greedy, or temperature and top-p (nucleus) sampling with a
  xorshift generator; exp is written out (range reduction and a Taylor
  series), since std has no safe exp.
- `check.vl`: `--check` (below).

## Verified

`./qwen35 --headless --check` (the output of the last run):

```
prompt 0: 5 tokens, ids match; greedy 24/24 steps match the reference; top-10 logits: largest difference 0.0001
prompt 1: 6 tokens, ids match; greedy 24/24 steps match the reference; top-10 logits: largest difference 0.0001
prompt 2: 20 tokens, ids match; greedy 24/24 steps match the reference; top-10 logits: largest difference 0.0001
tokenizer: 3 reference strings, ids and decoding match
check: PASS; largest top-10 logit difference over all prompts 0.0001
```

How: `reference/reference.json` (transformers, CPU, float32) gives the token ids
of three prompts (plain text, code, a chat turn), the greedy continuation
of 24 tokens, and the top-10 logits at each step. `--check` encodes each
prompt and compares the ids; then it runs the model over the prompt and
then over the reference's greedy tokens (teacher forcing, so the state is
the reference's at every step), and at each step compares the argmax with
the greedy token and our logits for the reference's top-10 ids with the
reference's top-10 logits. It also encodes and decodes the three
`tokenizer_only` strings (Unicode, tabs, newlines, special tokens) and compares.
The three prompts are run one after the other with the states reset
between them.

Also: `volec test main.vl` passes 5 tests (exp accuracy, decimal parsing,
the GPT-2 byte table, the pre-tokenizer splits on a sample string and on
contractions and digits).

Speed (through gpu-run, on a shared machine; numbers vary with other load):
decode about 58 to 60 tokens/s, prefill about 50 tokens/s (prefill runs one
token at a time through the same path; see ANALYSIS.md).

The window: a 120-frame run with a message sent streams its reply and quits
by itself. A headless `--shot` renders one frame of the chat into a texture,
writes a PPM, and was checked by eye (the text, the input line and the
status line are where they should be).

## Limits and approximations

- Context: 2048 positions (the attention kernel's shared memory and the KV
  cache size).
- Prefill is one token at a time, so it is no faster per token than decode.
- Only the text model: the vision tower and the multi-token-prediction head
  are not loaded.
- The pre-tokenizer decides \p{L} and \p{N} by Unicode ranges, not tables.
  ASCII and the common scripts and punctuation blocks are right; text is
  assumed to be NFC (no normalization is done).
- The added-token list and the chat template are written in the program
  (the 26 added tokens of tokenizer.json, one user turn); the template text
  is the one the reference uses.
- Activations are f32; weights are bf16, read in the kernels.
- The window's text is ASCII: other characters show as `?`.
