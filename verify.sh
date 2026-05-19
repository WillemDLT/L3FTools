#!/bin/bash
# L3FTools project verifier. Run after every edit pass.
set -e
cd "$(dirname "$0")"

python << 'PYEOF'
import os, sys, subprocess, re

def check(t):
    bd = 0; pd = 0; in_str = False; i = 0
    while i < len(t):
        c = t[i]
        if in_str:
            if c == '\\' and i+1 < len(t): i += 2; continue
            if c == '"': in_str = False
        else:
            if c == '"': in_str = True
            elif c == '-' and i+1 < len(t) and t[i+1] == '-':
                while i < len(t) and t[i] != '\n': i += 1
                continue
            elif c == '{': bd += 1
            elif c == '}': bd -= 1
            elif c == '(': pd += 1
            elif c == ')': pd -= 1
        i += 1
    last = ""
    for line in t.rstrip().split('\n')[::-1]:
        if line.strip(): last = line.strip(); break
    return bd, pd, last

def clean_end(last):
    if last.startswith('--'): return True
    if last.endswith(('end', ')', '}', ',', 'true', 'false', '"', ']')): return True
    if '=' in last and not last.endswith('='): return True
    return False

def lua_block_balance(t):
    # Strip "..." / '...' strings and -- line comments, then stack-match
    # Lua block keywords. Catches an orphaned, duplicated or missing
    # 'end' - a syntax error the brace check above cannot detect.
    code = []
    i = 0; q = None
    while i < len(t):
        c = t[i]
        if q:
            if c == '\\' and i+1 < len(t): code.append('  '); i += 2; continue
            if c == q: q = None
            code.append(' '); i += 1; continue
        if c == '"' or c == "'":
            q = c; code.append(' '); i += 1; continue
        if c == '-' and i+1 < len(t) and t[i+1] == '-':
            while i < len(t) and t[i] != '\n': code.append(' '); i += 1
            continue
        code.append(c); i += 1
    stack = []
    for m in re.finditer(r"\b(function|if|for|while|do|repeat|end|until)\b", ''.join(code)):
        k = m.group(1)
        if k == "function" or k == "if" or k == "repeat":
            stack.append(k)
        elif k == "for" or k == "while":
            stack.append("await")
        elif k == "do":
            if stack and stack[-1] == "await": stack[-1] = "loop"
            else: stack.append("do")
        elif k == "end":
            if not stack:
                return "unexpected 'end' (orphaned - stray or duplicated block)"
            if stack.pop() == "repeat":
                return "'end' where 'until' expected (repeat block)"
        elif k == "until":
            if not stack or stack.pop() != "repeat":
                return "'until' with no matching 'repeat'"
    if stack:
        return "%d unclosed block(s) - missing 'end'" % len(stack)
    return None

bad = []
print("=== Brace/paren balance + truncation checks ===")
for root, dirs, files in os.walk('.'):
    if '.git' in root: continue
    for fn in sorted(files):
        if not fn.endswith('.lua'): continue
        fp = os.path.join(root, fn)
        with open(fp, 'rb') as f: raw = f.read()
        if b'\x00' in raw:
            print(f"  FAIL   {fp[2:]}: contains NULL bytes (truncation residue)")
            bad.append(fp); continue
        t = raw.decode('utf-8', errors='replace')
        bd, pd, last = check(t)
        issues = []
        if bd != 0: issues.append(f"braces {bd:+d}")
        if pd != 0: issues.append(f"parens {pd:+d}")
        if not clean_end(last):
            issues.append(f"suspicious last line: {last[:50]}")
        block_issue = lua_block_balance(t)
        if block_issue:
            issues.append(block_issue)
        if issues:
            print(f"  FAIL   {fp[2:]}: " + "; ".join(issues))
            bad.append(fp)
        else:
            print(f"  OK     {fp[2:]}")

print()
print("=== Key function presence ===")
required = [
    "function L3F:RegisterRaid",
    "function L3F.RegisterDrops",
    "L3F.AutomarkerTryMark",
    "function L3F.SaveProfile",
    "function L3F.SyncActiveProfile",
]
miss = []
for fn in required:
    r = subprocess.run(["grep", "-rq", fn, "--include=*.lua", "."])
    if r.returncode != 0:
        print(f"  FAIL   missing: {fn}"); miss.append(fn)
    else:
        print(f"  OK     {fn}")

print()
print("=== Bindings.xml sanity ===")
bind_bad = 0
toc_files = [f for f in os.listdir('.') if f.endswith('.toc')]
if not os.path.exists("Bindings.xml"):
    print("  WARN   Bindings.xml not found - keybind feature disabled")
else:
    print("  OK     Bindings.xml present")
for tf in sorted(toc_files):
    listed = False
    with open(tf, encoding='utf-8', errors='replace') as f:
        for line in f:
            if line.strip().lower() == "bindings.xml":
                listed = True
    if listed:
        print(f"  FAIL   {tf} lists Bindings.xml - it is auto-loaded; listing it triggers 'Unrecognized XML: Binding'")
        bind_bad += 1
    else:
        print(f"  OK     {tf} does not list Bindings.xml")

print()
print("=== TOC load order ===")
toc_ok = True
if os.path.exists("L3FTools.toc"):
    with open("L3FTools.toc") as f: toc = f.read()
    for required_line in ["Core.lua", "Engine.lua"]:
        if required_line not in toc:
            print(f"  FAIL   {required_line} missing from toc"); toc_ok = False
        else:
            print(f"  OK     {required_line} listed")
else:
    print("  FAIL   L3FTools.toc missing"); toc_ok = False

print()
print("=== Duplicate NPC id check ===")
npc_names = {}
dup = 0
for root, dirs, files in os.walk('.'):
    if '.git' in root: continue
    for fn in sorted(files):
        if not fn.endswith('.lua'): continue
        fp = os.path.join(root, fn)
        with open(fp, encoding='utf-8', errors='replace') as f:
            for ln, line in enumerate(f, 1):
                m = re.search(r'id\s*=\s*(\d+)\s*,\s*name\s*=\s*"([^"]*)".*marks\s*=', line)
                if m:
                    npc_names.setdefault(m.group(1), {}).setdefault(m.group(2), []).append(f"{fp[2:]}:{ln}")
for nid, names in sorted(npc_names.items()):
    if len(names) > 1:
        detail = "; ".join(f'"{nm}" @{locs[0]}' for nm, locs in names.items())
        print(f"  FAIL   npc id {nid} -> {len(names)} different names: {detail}")
        dup += 1
if dup == 0:
    print(f"  OK     {len(npc_names)} unique npc ids, no id/name conflicts")

print()
print("=== Sections cross-check (Sections/ vs Data/) ===")
sec_bad = 0
sec_warn = 0
if os.path.isdir("Sections"):
    npc_re = re.compile(r'id\s*=\s*(\d+)\s*,\s*name\s*=\s*"([^"]*)"')
    for fn in sorted(os.listdir("Sections")):
        if not fn.endswith('.lua'): continue
        sec_fp = os.path.join("Sections", fn)
        data_fp = os.path.join("Data", fn)
        if not os.path.exists(data_fp):
            print(f"  FAIL   {sec_fp}: no matching Data/{fn} registry")
            sec_bad += 1; continue
        data_ids = {}
        with open(data_fp, encoding='utf-8', errors='replace') as f:
            for line in f:
                m = npc_re.search(line)
                if m: data_ids[m.group(1)] = m.group(2)
        fails = []; warns = []; checked = 0
        with open(sec_fp, encoding='utf-8', errors='replace') as f:
            for ln, line in enumerate(f, 1):
                m = npc_re.search(line)
                if not m: continue
                checked += 1
                sid, sname = m.group(1), m.group(2)
                if sid not in data_ids:
                    warns.append(f'line {ln}: id {sid} ("{sname}") absent from Data/{fn} - will not be auto-marked')
                elif data_ids[sid] != sname:
                    fails.append(f'line {ln}: id {sid} name "{sname}" != Data name "{data_ids[sid]}"')
        for w in warns: print(f"  WARN   {sec_fp}: {w}")
        for p in fails: print(f"  FAIL   {sec_fp}: {p}")
        sec_bad += len(fails); sec_warn += len(warns)
        if not fails and not warns:
            print(f"  OK     {sec_fp} ({checked} entries match Data/{fn})")
else:
    print("  (no Sections/ directory yet)")

print()
warn_note = f", {sec_warn} section warnings" if sec_warn else ""
print(f"Summary: {len(bad)} file failures, {len(miss)} missing functions, {dup} id conflicts, {sec_bad} section mismatches, {bind_bad} bindings issues{warn_note}")
sys.exit(1 if (bad or miss or dup or sec_bad or bind_bad or not toc_ok) else 0)
PYEOF
