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
printf '%s\n' '#include <stdint.h>' 'extern int64_t lil_entry(int64_t, int64_t);' 'int main(void) { const int64_t cases[][3] = {{0,0,0},{20,22,42},{-1,1,0},{9223372036854775807LL,0,9223372036854775807LL},{(-9223372036854775807LL-1),0,(-9223372036854775807LL-1)}}; for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; ++i) if (lil_entry(cases[i][0], cases[i][1]) != cases[i][2]) return 1; return 0; }' > "$lil_tmpdir/wrapper.c"
zig cc -c "$lil_tmpdir/wrapper.c" -o "$lil_tmpdir/wrapper.o"
zig build-exe -lc "$lil_tmpdir/program.ll" "$lil_tmpdir/wrapper.o" -femit-bin="$lil_output"
