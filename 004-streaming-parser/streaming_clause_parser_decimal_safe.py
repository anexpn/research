#!/usr/bin/env python3

"""Async streaming clause parser that is safe for decimal numbers.

Clauses are split by comma and period, except when a period is part of a
decimal number such as 3.14.
"""

from __future__ import annotations

import asyncio
from time import perf_counter
from typing import AsyncIterable, AsyncIterator


CHUNKS = [
    "The answer is 3.",
    "14, and pi appears in many formulas.",
    " Another value is 2.",
    "0. End of demo.",
]


def elapsed(start: float) -> str:
    return f"+{perf_counter() - start:0.2f}s"


async def simulated_english_chunk_stream(
    chunks: list[str], start: float, interval_s: float = 0.5
) -> AsyncIterator[str]:
    for chunk in chunks:
        await asyncio.sleep(interval_s)
        print(f"{elapsed(start)} chunk arrived: {chunk!r}")
        yield chunk


def find_clause_boundary(text: str, *, final: bool) -> int | None:
    """Return delimiter index for next clause boundary, or None if not ready."""
    for idx, char in enumerate(text):
        if char == ",":
            return idx

        if char != ".":
            continue

        prev_is_digit = idx > 0 and text[idx - 1].isdigit()
        has_next = idx + 1 < len(text)
        next_is_digit = has_next and text[idx + 1].isdigit()

        # Decimal point like 3.14 should not split.
        if prev_is_digit and next_is_digit:
            continue

        # If buffer currently ends at "3.", wait for next chunk to disambiguate.
        if prev_is_digit and not has_next and not final:
            return None

        return idx

    return None


async def clause_generator_decimal_safe(
    chunk_stream: AsyncIterable[str],
) -> AsyncIterator[str]:
    pending = ""

    async for chunk in chunk_stream:
        pending += chunk
        while True:
            split_idx = find_clause_boundary(pending, final=False)
            if split_idx is None:
                break
            clause = pending[:split_idx].strip()
            if clause:
                yield clause
            pending = pending[split_idx + 1 :]

    while True:
        split_idx = find_clause_boundary(pending, final=True)
        if split_idx is None:
            break
        clause = pending[:split_idx].strip()
        if clause:
            yield clause
        pending = pending[split_idx + 1 :]

    tail = pending.strip()
    if tail:
        yield tail


async def consume_clauses(start: float) -> list[str]:
    parsed: list[str] = []
    async for clause in clause_generator_decimal_safe(
        simulated_english_chunk_stream(CHUNKS, start, interval_s=0.5)
    ):
        print(f"{elapsed(start)} clause parsed: {clause!r}")
        parsed.append(clause)
    return parsed


async def main() -> int:
    start = perf_counter()
    clauses = await consume_clauses(start)
    print("\nAll parsed clauses:")
    for idx, clause in enumerate(clauses, start=1):
        print(f"{idx}. {clause}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
