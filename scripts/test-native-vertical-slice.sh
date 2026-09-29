#!/usr/bin/env bash
set -euo pipefail

lil_tmpdir="$(mktemp -d)"
trap 'rm -rf "$lil_tmpdir"' EXIT

zig build run -- lower-llvm fixtures/valid/minimal-macos.json > "$lil_tmpdir/minimal.ll"
zig build-exe -lc "$lil_tmpdir/minimal.ll" -femit-bin="$lil_tmpdir/minimal"

if "$lil_tmpdir/minimal"; then
  echo "expected native program to return 42, got 0" >&2
  exit 1
else
  lil_status=$?
  test "$lil_status" -eq 42
fi
