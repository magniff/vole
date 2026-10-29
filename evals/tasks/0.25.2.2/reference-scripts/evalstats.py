import json, re, sys, collections, os
SUBS = ["check","test","guide","query","edit","refactor","fix","explain","probe","reduce","fmt","try","build"]
def stats(path):
    tools = collections.Counter(); volec = collections.Counter(); blocks = collections.Counter()
    autofix = 0; errors_tool = 0; changed_disk = 0; seen = set()
    for line in open(path, encoding="utf-8", errors="replace"):
        try: e = json.loads(line)
        except Exception: continue
        m = e.get("message") or {}
        c = m.get("content")
        if not isinstance(c, list): continue
        for b in c:
            if not isinstance(b, dict): continue
            bid = b.get("id") or b.get("tool_use_id")
            if bid:
                key = (b.get("type"), bid)
                if key in seen: continue
                seen.add(key)
            if b.get("type") == "tool_use":
                n = b.get("name"); tools[n] += 1
                if n == "Bash":
                    cmd = b.get("input", {}).get("command", "")
                    for mm in re.finditer(r'volec(?:-[\w.]+)?\s+(?:-\S+\s+)*([a-z]+|\S+\.vl)', cmd):
                        s = mm.group(1)
                        s = "build" if (s.endswith(".vl") or s == "main") else s
                        if s == "query":
                            q = re.search(r'volec\s+query\s+([a-z]+)', cmd[mm.start():])
                            s = "query " + (q.group(1) if q else "?")
                        volec[s] += 1
            elif b.get("type") == "tool_result":
                t = b.get("content")
                t = json.dumps(t) if not isinstance(t, str) else t
                for k in re.findall(r'blocked hook\.([a-z-]+)', t): blocks[k] += 1
                if b.get("is_error"): errors_tool += 1
                autofix += len(re.findall(r'\bfixed [^\s]+\.vl:\d+', t))
                changed_disk += len(re.findall(r'modified (?:on disk )?since', t))
    return tools, volec, blocks, autofix, errors_tool, changed_disk
rows = []
for name, path in [a.split("=") for a in sys.argv[1:]]:
    rows.append((name,) + stats(path))
print("| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |")
print("|---|---|---|---|---|---|---|---|---|")
for name, tools, volec, blocks, autofix, err, chg in rows:
    tot = sum(v for k, v in tools.items() if k != "SubagentHandback")
    vs = ", ".join(f"{k} {v}" for k, v in volec.most_common(8))
    bl = sum(blocks.values())
    print(f"| {name} | {tot} | {tools['Bash']} | {tools['Edit']} | {tools['Write']} | {tools['Read']} | {vs} | {bl} ({', '.join(f'{k} {v}' for k,v in blocks.items())}) | {err} |")
