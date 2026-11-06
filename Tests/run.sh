#!/bin/zsh
# Self-check for the non-UI code: every Model and Service + Tests/main.swift. New services are picked up automatically.
set -euo pipefail
cd "${0:A:h}/.."
out="${TMPDIR:-/tmp}/gv-check"
swiftc GateView/Models/*.swift GateView/Services/*.swift Tests/main.swift -o "$out"
"$out"
