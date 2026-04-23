#!/usr/bin/env python3

"""Async streaming clause parser with configurable wrapper skipping.

Features:
- Clauses split by comma and period
- Decimal-safe period handling (3.14 is not split)
- Optional skipping of wrapped content in () and {}, even across chunk boundaries
- If a wrapper is left open at end-of-stream, its buffered content is emitted
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from time import perf_counter
from typing import AsyncIterator


CHUNKS = [
    "The value is 3.",
    "14, keep this (drop this part.",
    " still inside (nested, still hidden)), then continue.",
    " Another clause (ignore",
    " me, even with (deep, nested) commas.) ends here.",
    " Last one (outer (inner",
    " with 9.99, and commas.) still outer) done.",
    " Curly demo {hide this, and this.",
    " still hidden} visible again.",
    " Mixed {(nested braces, and parens)} final clause.",
    " Unclosed case starts (keep this text, even with commas",
    " and 7.5 as-is",
]


@dataclass
class ParseConfig:
    skip_wrapped: bool = True


def elapsed(start: float) -> str:
    return f"+{perf_counter() - start:0.2f}s"


def normalize_whitespace(text: str) -> str:
    return " ".join(text.split())


async def simulated_chunk_stream(
    chunks: list[str], start: float, interval_s: float = 0.5
) -> AsyncIterator[str]:
    """Yield chunks at fixed intervals to mimic streaming arrival."""
    for chunk in chunks:
        await asyncio.sleep(interval_s)
        print(f"{elapsed(start)} chunk arrived: {chunk!r}")
        yield chunk


async def clause_generator(
    chunk_stream: AsyncIterator[str],
    *,
    config: ParseConfig,
) -> AsyncIterator[str]:
    """Yield clauses with decimal and ()/{} wrapper handling."""
    pending: list[str] = []
    paren_depth = 0
    brace_depth = 0
    skipped_wrapped_buffer: list[str] = []
    pending_dot_after_digit = False

    async for chunk in chunk_stream:
        for ch in chunk:
            # Resolve ambiguous "digit + ." once next char arrives.
            if pending_dot_after_digit:
                if ch.isdigit():
                    # Decimal fraction: keep the dot and continue normally.
                    pending.append(".")
                else:
                    # Sentence delimiter after a number.
                    clause = normalize_whitespace("".join(pending).strip())
                    if clause:
                        yield clause
                    pending.clear()
                pending_dot_after_digit = False

            # Optional wrapper stripping with cross-chunk depth tracking.
            if config.skip_wrapped:
                in_wrapper = paren_depth > 0 or brace_depth > 0

                if ch == "(":
                    if not in_wrapper:
                        skipped_wrapped_buffer.clear()
                    paren_depth += 1
                    skipped_wrapped_buffer.append(ch)
                    continue
                if ch == "{":
                    if not in_wrapper:
                        skipped_wrapped_buffer.clear()
                    brace_depth += 1
                    skipped_wrapped_buffer.append(ch)
                    continue

                if in_wrapper:
                    skipped_wrapped_buffer.append(ch)
                    if ch == ")" and paren_depth > 0:
                        paren_depth -= 1
                    elif ch == "}" and brace_depth > 0:
                        brace_depth -= 1

                    # Balanced wrapper: permanently drop buffered wrapped text.
                    if paren_depth == 0 and brace_depth == 0:
                        skipped_wrapped_buffer.clear()
                    continue

            if ch == ",":
                clause = normalize_whitespace("".join(pending).strip())
                if clause:
                    yield clause
                pending.clear()
                continue

            if ch == ".":
                # Decimal-safe: delay decision if dot follows a digit.
                prev_char = pending[-1] if pending else ""

                if prev_char.isdigit():
                    pending_dot_after_digit = True
                    continue

                clause = normalize_whitespace("".join(pending).strip())
                if clause:
                    yield clause
                pending.clear()
                continue

            pending.append(ch)

    # If stream ends with unclosed wrappers, keep remaining buffered text.
    if config.skip_wrapped and (paren_depth > 0 or brace_depth > 0):
        pending.extend(skipped_wrapped_buffer)

    # Finalization pass:
    if pending_dot_after_digit:
        clause = normalize_whitespace("".join(pending).strip())
        if clause:
            yield clause
        pending.clear()

    tail = normalize_whitespace("".join(pending).strip())
    if tail:
        yield tail


async def consume_clauses(start: float, config: ParseConfig) -> list[str]:
    parsed: list[str] = []
    async for clause in clause_generator(
        simulated_chunk_stream(CHUNKS, start, interval_s=0.5),
        config=config,
    ):
        print(f"{elapsed(start)} clause parsed: {clause!r}")
        parsed.append(clause)
    return parsed


async def main() -> int:
    start = perf_counter()

    config = ParseConfig(skip_wrapped=True)
    print(f"Config: skip_wrapped={config.skip_wrapped}\n")
    clauses = await consume_clauses(start, config)

    print("\nAll parsed clauses:")
    for idx, clause in enumerate(clauses, start=1):
        print(f"{idx}. {clause}")

    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
