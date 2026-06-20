#!/usr/bin/env python3
"""ac.py — atomic-only hands for a same-model (Claude) ATOMIC arm.

Reuses the PROVEN atomic_call() from local_atomic_agent (absolutizes paths to the workdir + jails to it),
so a Claude subagent can drive the atomic engine reliably. The atomic-Claude arm must use ONLY this for
code reads/edits — never native Read/Edit/Write/Grep/Glob.

Usage: python3 ac.py <workdir> <tool> '<json-args>'   (paths may be repo-root-relative)
Tools: atomic_grep {"pattern","path?","glob?","contextAfter?"} | code_outline_batch {"glob"} |
       code_readcode {"path","selector?","maxFullChars?"} |
       atomic_read_file {"file","startLine","endLine","includeContent":true}  (LINE RANGE) |
       atomic_replace_text {"file","oldText","newText","proofOfIncorrectness?"} |
       atomic_create_file {"file","content"}
"""
import os, sys, json
os.environ.setdefault("DEEPSEEK_API_KEY", "unused-for-atomic-call")  # let import succeed (atomic_call needs no key)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import local_atomic_agent as A

wd, tool = sys.argv[1], sys.argv[2]
try:
    args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
except Exception:
    args = {"path": sys.argv[3]} if len(sys.argv) > 3 else {}
res, ok = A.atomic_call(wd, tool, args)
print(res)
