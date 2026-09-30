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
`8122 7201 7202` creates `add.wrapping<i64>(arg0,arg1)`.

**Comparison contract:** inputs satisfy `INT64_MIN ≤ arg0 + arg1 ≤ INT64_MAX`.
Within that domain, LIL’s wrapping add and C’s signed add have the same result.
Overflow policy is intentionally excluded from this first pipeline test.

### 3. Debugger view

`F[2,L,L>L](+[0,1])` is a debugger mnemonic, not the model output. The human
view is [arithmetic.lil](arithmetic.lil):

```text
function (arg0: i64, arg1: i64) -> i64
  add(arg0, arg1)
```

Inspect the binary artifact without parsing source:

```sh
./lil debug add_i64.lil
```

### 4. Build an executable

The model runtime writes its raw output to the opaque binary artifact
`add_i64.lil`. For local development, `pack` is only an ingestion convenience:

```sh
./lil pack 1847,3912,3912,3912,8122,7201,7202 -o add_i64.lil
./lil debug add_i64.lil
./lil build add_i64.lil -o lil-add
./lil-add
```

`build` owns the backend wrapper and linker invocation. The wrapper calls the
same `i64(i64,i64)` function boundary; it is compiler build configuration, not
model output.

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
```

### 3. Build an executable

```sh
gcc -O3 -std=c11 -c add_i64.c -o add_i64.o
gcc -O3 -std=c11 add_i64.o external_harness.c -o c-add
./c-add
```

`external_harness.c` contains the same input table and no-overflow contract as
the LIL build wrapper. It is deliberately outside the generated C function.

## Performance

| Metric | LIL | C | Status |
| --- | ---: | ---: | --- |
| Correctness harness | same external input table | same external input table | runnable |
| Native runtime | not measured | not measured | requires fixed benchmark harness and target |
| Native binary size | not measured | not measured | requires identical linker/debug settings |
| Compile time | not measured | not measured | requires repeated cold/warm runs |

No performance value is claimed until both artifacts run the same workload on
the same target with published commands and compiler versions.

## Token generation

| Representation | Model output required | Count | Status |
| --- | --- | ---: | --- |
| LIL `lil.graph/1` | `1847 3912 3912 3912 8122 7201 7202` | 7 semantic IDs | exact ABI count, not yet a model-token measurement |
| C | C source above | not measured | requires one named model/tokenizer and an actual generation trace |

The sequence is seven generated model tokens only if the selected model’s
vocabulary maps each LIL ID to exactly one output token and the inference trace
records those output IDs. Decimal text in a chat response is not that trace.
The evaluation harness records tokenizer/model identity so a real comparison
can be reproduced.
