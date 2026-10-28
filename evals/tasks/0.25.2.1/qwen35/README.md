# qwen35: eval record (vole 0.25.2.1, round 2)

One of ten GPU demos built by AI agents in the second round of the vole eval loop (round 1, on vole 0.25.2, is [../../0.25.2/qwen35/](../../0.25.2/qwen35/)) (see [../SUMMARY.md](../SUMMARY.md)).

| | |
|---|---|
| model | Claude Haiku 5.5 (`claude-haiku-5-5`) |
| reasoning effort | medium |
| agent | Claude Code subagent, type `general-purpose`, run in the background by the orchestrator (Claude Opus 5.5) |
| harness | Claude Code with the repository's hooks (check after every edit with automatic `fix --suggested`, query-first, turn-end) |
| compiler | vole 0.25.2.1 (`target/volec`, tag `v0.25.2.1`, commit 28e78c2a) |
| started | 2026-10-28 22:26 CET |
| duration | 24.1 min (1449 s) |
| tokens | 362,352 (as reported by the harness) |
| tool calls | 113 |
| shared machine | up to 5 agents at once; GPU programs run through [`../tools/gpu-run`](../tools/gpu-run) (one at a time) |

## Files

- [ANALYSIS.md](ANALYSIS.md): the agent's own report (tools used, what went well and badly, suggestions), asked to be brutally honest. Where the harness refused the agent's write, the orchestrator saved it verbatim from the agent's final message (the file says so).
- [REVIEW.md](REVIEW.md): the review of its code and claims.
- [PROGRAM.md](PROGRAM.md): the agent's README for its program (how to build and run it, controls, what it verified).
- The program: `main.vl` and its modules; build with `volec main.vl -o qwen35`.

## The prompt

The agent got this prompt, verbatim, and read the shared brief [../BRIEF.md](../BRIEF.md) as it says. The brief is round 1's with the paths changed and round 1's harness notes folded in; every agent saw the same brief.

```
You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `qwen35`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/qwen35/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `qwen35`.

Your task:

Run Qwen3.5-0.8B, a real open-weights LLM, on the GPU, from vole. Text only (ignore the vision tower). The model is in /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/qwen35/model/ (a symlink: config.json, model.safetensors-00001-of-00001.safetensors in bf16, tokenizer.json, vocab.json, merges.txt, tokenizer_config.json, chat_template.jinja); read it at run time, never copy it. The architecture: 24 decoder layers, 18 Gated DeltaNet linear-attention layers and every fourth layer gated full attention (GQA 8 query heads over 2 KV heads, head_dim 256, partial RoPE on a quarter of each head, theta 1e7, an output gate), RMSNorm, a SwiGLU MLP, tied embeddings, vocab 248,320. The reference implementation to read is reference/modeling_qwen3_5.py (Hugging Face transformers) in your folder; reference/reference.json holds ground truth computed by it on the CPU: the token ids of several prompts, the greedy continuation's token ids and text, and the top-10 logits at each step. Build: a safetensors reader, the byte-level BPE tokenizer (encode and decode), the forward pass as WGSL compute kernels (bf16 weights converted or read in the kernels, matrix-vector products, RMSNorm, the causal conv1d and the gated delta-rule recurrence for the linear layers with their state carried between tokens, attention with a KV cache, RoPE, SwiGLU, the LM head), greedy and temperature/top-p sampling, and the chat template. Correctness first: `--headless --check` must reproduce reference.json's prompt token ids exactly and its greedy continuation (the same token ids, the top logits close), and say how close; then speed (print tokens per second for prefill and decode). The window is a chat: type a message, the answer streams in token by token, with the tokens per second shown. Headless: `--prompt TEXT --tokens N` prints the continuation. A CPU implementation of a step is a fine way to get correct first, but the finished program runs the model on the GPU.
```

## Tool use, from the transcript

Counted from the agent's transcript (tool calls deduplicated; `volec` subcommands parsed from every shell command; "hook blocks" are commands refused by tools/agent-hooks):

| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |
|---|---|---|---|---|---|---|---|---|
| qwen35 | 112 | 100 | 0 | 4 | 1 | build 24, query items 15, guide 10, query show 10, check 8, test 4, query context 1 | 1 (query-first 1) | 9 |
