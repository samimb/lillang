# End-to-end comparison: `add_i64`

This is the intended evaluation shape: same task, model-only output, debugger
projection, compiler build, and a conventional-language baseline. LIL’s model
output is raw token IDs; all text below is documentation or build configuration.

## LIL

### 1. Prompt

```text
Using LIL, build an i64 function that adds its two arguments. Only give code output.
```

### 2. Generated code

```text
1847 3912 3912 3912 8122 7201 7202
```

Those seven `u16` IDs are the program. `1847` is the ABI token for an anonymous
two-input function frame; the three `3912`s fill its input/result type slots;
`8122 7201 7202` creates `add<i64>(arg0,arg1)`.

### 3. Debugger view

`F[2,L,L>L](+[0,1])` is a debugger mnemonic, not the model output. The human
view is [arithmetic.lil](arithmetic.lil):

```text
function (arg0: i64, arg1: i64) -> i64
  add(arg0, arg1)
```

Inspect the backend projection without parsing source:

```sh
zig build run -- lower-function-graph-v1 1847,3912,3912,3912,8122,7201,7202
```

### 4. Build an executable

```sh
bash scripts/build-function-graph-v1-demo.sh \
  1847,3912,3912,3912,8122,7201,7202 ./lil-add
./lil-add
```

The wrapper that calls `lil_entry(20, 22)` is compiler/build configuration. It
is not model output and does not change the latent function graph.

## C

### 1. Prompt

```text
Using C, build an i64 function that adds its two arguments. Only give code output.
```

### 2. Generated code

```c
#include <stdint.h>

int64_t add_i64(int64_t arg0, int64_t arg1) {
    return arg0 + arg1;
}

int main(void) {
    return add_i64(20, 22) == 42 ? 0 : 1;
}
```

### 3. Build an executable

```sh
gcc -O3 -std=c11 add_i64.c -o c-add
./c-add
```

## Performance

| Metric | LIL | C | Status |
| --- | ---: | ---: | --- |
| Correctness harness | exit 0 expected | exit 0 expected | runnable |
| Native runtime | not measured | not measured | requires fixed benchmark harness and target |
| Native binary size | not measured | not measured | requires identical linker/debug settings |
| Compile time | not measured | not measured | requires repeated cold/warm runs |

No performance value is claimed until both artifacts run the same workload on
the same target with published commands and compiler versions.

## Token generation

| Representation | Model output required | Count | Status |
| --- | --- | ---: | --- |
| LIL `lil.graph/1` | `1847 3912 3912 3912 8122 7201 7202` | 7 semantic tokens | exact ABI count |
| C | C source above | not measured | requires one named model/tokenizer and an actual generation trace |

Comparing LIL’s seven semantic tokens to an invented C-token count would be
misleading. The evaluation harness records tokenizer/model identity so a real
comparison can be reproduced.
