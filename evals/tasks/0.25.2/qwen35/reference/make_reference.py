"""Ground truth for the qwen35 eval task: Hugging Face transformers runs
Qwen3.5-0.8B (text only) on the CPU in float32 (the bf16 weights widened,
exactly) and records, for a few prompts: the token ids, the greedy
continuation (ids and text), the top-10 logits at each step, and for the
first prompt the hidden state after every layer at the last position (its
RMS and first 8 values), to localise a wrong layer.

usage: ~/models/venv-ref/bin/python make_reference.py MODEL_DIR OUT.json
"""
import json
import sys

import torch
import transformers
from transformers import AutoModelForCausalLM, AutoTokenizer

model_dir, out = sys.argv[1], sys.argv[2]
torch.manual_seed(0)
tok = AutoTokenizer.from_pretrained(model_dir)
model = AutoModelForCausalLM.from_pretrained(model_dir, dtype=torch.float32)
model.eval()

STEPS = 24
chat = tok.apply_chat_template(
    [{"role": "user", "content": "Write a haiku about a GPU."}],
    tokenize=False, add_generation_prompt=True)
prompts = [
    ("plain", "The capital of France is"),
    ("code", "def fibonacci(n):\n    "),
    ("chat", chat),
]
tokenizer_only = [
    "Größe: 東京 🚀 naïve café — “quotes”\ttab\n\nnewlines   spaces",
    "<|im_start|>user\nhi<|im_end|>",
    "1234567 + 89 = 1234656",
]

result = {
    "model": "Qwen/Qwen3.5-0.8B",
    "made_by": "transformers %s, torch %s, CPU, float32 (bf16 weights widened), greedy" % (
        transformers.__version__, torch.__version__),
    "eos_token_ids": [tok.eos_token_id] if tok.eos_token_id is not None else [],
    "prompts": [],
    "tokenizer_only": [],
}

for text in tokenizer_only:
    ids = tok(text, add_special_tokens=False)["input_ids"]
    result["tokenizer_only"].append({"text": text, "ids": ids, "decoded": tok.decode(ids)})

with torch.no_grad():
    for name, text in prompts:
        ids = tok(text, add_special_tokens=False)["input_ids"]
        entry = {"name": name, "text": text, "ids": ids, "steps": []}
        cur = torch.tensor([ids])
        past = None
        generated = []
        for step in range(STEPS):
            want_hidden = (name == "plain" and step == 0)
            o = model(input_ids=cur, past_key_values=past, use_cache=True,
                      output_hidden_states=want_hidden)
            past = o.past_key_values
            logits = o.logits[0, -1].float()
            top = torch.topk(logits, 10)
            nxt = int(top.indices[0])
            entry["steps"].append({
                "top_ids": [int(i) for i in top.indices],
                "top_logits": [round(float(v), 4) for v in top.values],
            })
            if want_hidden:
                entry["hidden_last_position"] = [
                    {"after": "embeddings" if k == 0 else "layer %d" % (k - 1),
                     "rms": round(float(h[0, -1].pow(2).mean().sqrt()), 5),
                     "first8": [round(float(v), 5) for v in h[0, -1, :8]]}
                    for k, h in enumerate(o.hidden_states)]
            generated.append(nxt)
            cur = torch.tensor([[nxt]])
        entry["greedy_ids"] = generated
        entry["greedy_text"] = tok.decode(generated)
        result["prompts"].append(entry)
        print(name, repr(entry["greedy_text"]))

with open(out, "w") as fh:
    json.dump(result, fh, indent=1, ensure_ascii=False)
print("wrote", out)
