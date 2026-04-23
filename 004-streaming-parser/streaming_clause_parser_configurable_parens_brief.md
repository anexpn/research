## Final Solution Brief

This solution is a **stateful streaming clause parser** for incremental text input, where data arrives in chunks and clauses should be emitted as soon as possible.

### Core Idea

- Parse input **character by character** instead of waiting for full text.
- Maintain parser state across chunks so split boundaries are handled correctly.
- Emit a clause immediately when a true delimiter is confirmed.

### What State Is Tracked

- `pending`: accumulated visible text for the current clause.
- `pending_dot_after_digit`: remembers ambiguous `digit + "."` until the next character arrives.
- `paren_depth` and `brace_depth`: nesting depth for `()` and `{}`.
- `skipped_wrapped_buffer`: skipped wrapper content, used for end-of-stream recovery.

### Delimiter Rules

- `,` is a clause boundary (unless inside skipped wrappers).
- `.` is a clause boundary **except** when part of a decimal number.
  - If `.` follows a digit, delay decision until next character.
  - Next char digit => decimal (e.g., `3.14`), keep parsing same clause.
  - Next char non-digit => sentence boundary, emit clause.

### Wrapper Skipping (`skip_wrapped`)

When enabled:

- Content inside `()` and `{}` is skipped.
- Nested and mixed wrappers are supported via depth counters.
- Delimiters inside wrappers do not trigger clause emission.
- Works across chunk boundaries.

### End-of-Stream Recovery

If stream ends with unclosed wrappers, skipped text is not lost:

- buffered wrapped content is appended back to `pending`
- final tail is emitted as the last clause

This makes the parser robust to malformed/incomplete streams.

### Why This Design

- **Low latency:** emits clauses ASAP.
- **Streaming-safe:** correct across chunk boundaries.
- **Configurable:** wrapper skipping can be turned on/off.
- **Resilient:** handles decimals, nesting, and unclosed wrappers gracefully.