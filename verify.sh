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
print(f"Summary: {len(bad)} file failures, {len(miss)} missing functions, {dup} id conflicts")
sys.exit(1 if (bad or miss or dup or not toc_ok) else 0)
PYEOF
