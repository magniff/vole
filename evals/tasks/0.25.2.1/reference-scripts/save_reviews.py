"""save_reviews.py TRANSCRIPT DIR: split the reviewer's hand-back at
'=== REVIEW: NAME ===' lines and write DIR/NAME/REVIEW.md under the
orchestrator's note (refuses to overwrite)."""
import json, os, re, sys
path, root = sys.argv[1:3]
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
parts = re.split(r"^=== REVIEW: (\w+) ===\s*$", msg, flags=re.M)
note = ("> **How this review was made.** By a reviewer agent (Claude Opus 5.5) working to the orchestrator's rubric "
        "([../REVIEW-RUBRIC.md](../REVIEW-RUBRIC.md)): it rebuilt the program from a copy of the sources with vole 0.25.2.1, "
        "re-ran the tests and every headless check through gpu-run, and read all the code. Saved verbatim by the orchestrator.\n\n")
for name, body in zip(parts[1::2], parts[2::2]):
    out = os.path.join(root, name, "REVIEW.md")
    if os.path.exists(out):
        print(f"{out} exists, skipped"); continue
    open(out, "w").write(note + body.strip() + "\n")
    g = re.search(r"\*\*Grades:\*\*.*", body)
    print(f"{name}: {len(body.splitlines())} lines; {g.group(0) if g else 'NO GRADES'}")
