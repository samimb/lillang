#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: bash scripts/build-native.sh <snapshot.json> <output-path>" >&2
  exit 2
fi

lil_input="$1"
lil_output="$2"
lil_tmpdir="$(mktemp -d)"
trap 'rm -rf "$lil_tmpdir"' EXIT

zig build run -- check "$lil_input"
zig build run -- lower-llvm "$lil_input" > "$lil_tmpdir/program.ll"
zig build-exe -lc "$lil_tmpdir/program.ll" -femit-bin="$lil_output"
