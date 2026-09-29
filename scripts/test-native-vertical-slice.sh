#!/usr/bin/env bash
set -euo pipefail

lil_tmpdir="$(mktemp -d)"
trap 'rm -rf "$lil_tmpdir"' EXIT

zig build run -- lower-token-ids 1,16,32,6164,32,6166,33,12288,12289,34,12290,17,2 > "$lil_tmpdir/minimal.ll"
zig build-exe -lc "$lil_tmpdir/minimal.ll" -femit-bin="$lil_tmpdir/minimal"

if "$lil_tmpdir/minimal"; then
  echo "expected native program to return 42, got 0" >&2
  exit 1
else
  lil_status=$?
  test "$lil_status" -eq 42
fi
