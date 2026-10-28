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
if not msg or "# ANALYSIS" not in msg:
    sys.exit(f"{name}: no '# ANALYSIS' in the hand-back")
body = msg[msg.index("# ANALYSIS"):]
body = body.split("\n", 1)[1].lstrip("\n")  # the agent's own title line
out = os.path.join(root, name, "ANALYSIS.md")
if os.path.exists(out):
    sys.exit(f"{out} exists")
note = (f"# {name}: the agent's analysis\n\n> Saved verbatim by the orchestrator from the agent's final message: "
        "the harness refused the agent's own write of this file (subagents may not write report files). "
        "Nothing is edited but this note and the headings' markup.\n\n")
open(out, "w").write(note + body.rstrip() + "\n")
print(f"wrote {out}: {len(body.splitlines())} lines")
