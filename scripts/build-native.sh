#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: bash scripts/build-native.sh <comma-separated-token-ids> <output-path>" >&2
  exit 2
fi

lil_token_ids="$1"
lil_output="$2"
lil_tmpdir="$(mktemp -d)"
trap 'rm -rf "$lil_tmpdir"' EXIT

zig build run -- check-token-ids "$lil_token_ids"
zig build run -- lower-token-ids "$lil_token_ids" > "$lil_tmpdir/program.ll"
zig build-exe -lc "$lil_tmpdir/program.ll" -femit-bin="$lil_output"
