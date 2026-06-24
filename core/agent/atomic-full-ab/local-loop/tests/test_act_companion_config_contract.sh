#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/setup.cfg" <<'CFG'
[options]
packages = find:
install_requires =
    astroid>=2.6.5,<2.7
    toml>=0.10.0

[isort]
known_third_party = astroid, toml

[mypy]
scripts_are_modules = True
CFG

python3 - "$tmp" <<'PY'
import pathlib
import sys

import local_atomic_agent as agent

workdir = pathlib.Path(sys.argv[1])
weight = {
    "class": "MISSED-COMPANION-CONFIG-FILE",
    "strategy": "After fixing code, check setup.cfg/pyproject metadata too.",
    "proof_n": 1,
    "act": {
        "preconditions": {"trigger": "configuration/path/registration"},
        "transformation": {"op": "apply_learned_resolution_operator"},
    },
}
task = "Make pylint XDG Base Directory Specification compliant and change default storage path."

assert agent._weight_requires_mandatory_application(weight, task), "companion-config ACT must be mandatory even with proof_n=1"
assert not agent._weight_requires_mandatory_application({"class": "READ-WRITE-ROUNDTRIP-SYMMETRY", "strategy": "roundtrip"}, task)

injection = agent._execute_companion_config_weight_operator(str(workdir), task)
assert "MANDATORY ACT APPLICATION" in injection
assert "setup.cfg" in injection
assert "install_requires" in injection
assert "known_third_party" in injection
assert "mypy" in injection
assert "Before the first edit" in injection
assert "appdirs" not in injection, "operator may expose metadata context but must not hardcode task-specific dependency"
PY

echo "ACT companion-config contract ok"
