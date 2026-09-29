# Token-cost evaluation harness v0

`zig build evaluate-token-cost` runs fixed token-ABI tasks and emits one TSV
record per task. It keeps model/tokenizer identifiers separate from decoder and
backend measurements so a tokenizer change cannot be mistaken for a compiler
regression.

The current `arithmetic.create` task records:

- semantic output token IDs accepted by `lil.token/0`;
- a native Zig baseline artifact and its byte count (not a fabricated tokenizer
  count);
- retrieval tokens, constrained retries, and tool calls;
- direct decode/validation time and LLVM-lowering time;
- ABI, compiler, backend, model, and tokenizer identities.

The built-in fixture has no model inference, retrieval, retries, or tools, so
those fields are explicitly zero and the identifiers are `fixture`. Real
experiments must replace them with observed values from a named model/tokenizer
and record the exact prompt/projection, retrieval events, retry policy, build
settings, native baseline, and target.

## Task corpus rules

Each task added to the harness MUST provide an equivalent native-language
baseline artifact and expected behavior. Implementation and patch tasks are
separate rows: a patch row is admitted only after the atomic graph-patch API
exists, so it can measure a real graph change rather than a regenerated full
program. Results MUST never compare raw token counts across tokenizers without
also reporting the tokenizer identity and full task success rate.
