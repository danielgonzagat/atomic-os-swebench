#!/usr/bin/env bash
# Regenerate the COMPLETE atomic bundle from the packaged engine (the bundle is gitignored:
# it is a reproducible build artifact, not source). Used by swe_modal_agent ATOMIC_MODE=full.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tar -czf "$HERE/../atomic-full-bundle.tgz" -C "$HERE/pkg" atomic-edit
echo "wrote $HERE/../atomic-full-bundle.tgz ($(du -h "$HERE/../atomic-full-bundle.tgz" | cut -f1))"
