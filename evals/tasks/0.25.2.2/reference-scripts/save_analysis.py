"""save_analysis.py NAME TRANSCRIPT DIR: write DIR/NAME/ANALYSIS.md from the
agent's SubagentHandback message, from its first '# ANALYSIS' heading on,
under the orchestrator's note. Refuses to overwrite an existing file."""
import json, os, sys
name, path, root = sys.argv[1:4]
msg = None
for line in open(path):
    try:
        o = json.loads(line)
    except ValueError:
        continue
    m = o.get("message", {})
    if m.get("role") != "assistant" or not isinstance(m.get("content"), list):
        continue
    for c in m["content"]:
        if c.get("type") == "tool_use" and "Handback" in c.get("name", ""):
            msg = c["input"].get("message", "")
if msg and "=== ANALYSIS ===" in msg:
    body = msg[msg.index("=== ANALYSIS ==="):].split("\n", 1)[1]
    if "=== END ANALYSIS ===" in body:
        body = body[:body.index("=== END ANALYSIS ===")]
    body = body.strip("\n") + "\n"
elif msg and "# ANALYSIS" in msg:
    body = msg[msg.index("# ANALYSIS"):]
    body = body.split("\n", 1)[1].lstrip("\n")  # the agent's own title line
elif msg and "## 1. Result" in msg:
    body = msg[msg.index("## 1. Result"):]
else:
    sys.exit(f"{name}: no '# ANALYSIS' in the hand-back")
# a closing rule of '=' and what follows it is the agent's note to the orchestrator
lines = body.rstrip().split("\n")
for i, l in enumerate(lines):
    if len(l) >= 10 and set(l.strip()) == {"="}:
        lines = lines[:i]
        break
body = "\n".join(lines).rstrip() + "\n"
out = os.path.join(root, name, "ANALYSIS.md")
if os.path.exists(out):
    sys.exit(f"{out} exists")
note = (f"# {name}: the agent's analysis\n\n> Saved verbatim by the orchestrator from the agent's final message: "
        "the harness refused the agent's own write of this file (subagents may not write report files). "
        "Nothing is edited but this note and the headings' markup.\n\n")
open(out, "w").write(note + body.rstrip() + "\n")
print(f"wrote {out}: {len(body.splitlines())} lines")
