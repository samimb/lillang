#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: bash scripts/build-function-graph-v1-demo.sh <comma-separated-token-ids> <output-path>" >&2
  exit 2
fi

lil_tokens="$1"
lil_output="$2"
lil_tmpdir="$(mktemp -d)"
trap 'rm -rf "$lil_tmpdir"' EXIT

zig build run -- lower-function-graph-v1 "$lil_tokens" > "$lil_tmpdir/program.ll"
printf '%s\n' 'extern long long lil_entry(long long, long long); int main(void) { return lil_entry(20, 22) == 42 ? 0 : 1; }' > "$lil_tmpdir/wrapper.c"
zig cc -c "$lil_tmpdir/wrapper.c" -o "$lil_tmpdir/wrapper.o"
zig build-exe -lc "$lil_tmpdir/program.ll" "$lil_tmpdir/wrapper.o" -femit-bin="$lil_output"
