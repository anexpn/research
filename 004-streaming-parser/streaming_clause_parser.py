#!/usr/bin/env python3

"""Async streaming clause parser demo.

Parses English text chunks into clauses separated by comma and period.
The consumer prints each parsed clause as soon as it is available.
"""

from __future__ import annotations

import asyncio
from time import perf_counter
from typing import AsyncIterable, AsyncIterator


CHUNKS = [
    "When data arrives in pieces,",
    " a parser should not wait for the full",
    " document. It should emit each clause",
    " as soon as a delimiter appears,",
    " so downstream tasks can start early.",
]


def elapsed(start: float) -> str:
    return f"+{perf_counter() - start:0.2f}s"


async def simulated_english_chunk_stream(
    chunks: list[str], start: float, interval_s: float = 0.5
) -> AsyncIterator[str]:
    """Yield English chunks at fixed intervals to mimic network streaming."""
    for chunk in chunks:
        await asyncio.sleep(interval_s)
        print(f"{elapsed(start)} chunk arrived: {chunk!r}")
        yield chunk


async def clause_generator(chunk_stream: AsyncIterable[str]) -> AsyncIterator[str]:
    """Yield clauses split by comma and period from async chunk source."""
    pending = ""
    delimiters = {",", "."}

    async for chunk in chunk_stream:
        pending += chunk
        while True:
            split_idx = None
            for i, char in enumerate(pending):
                if char in delimiters:
                    split_idx = i
                    break

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
    """Consume clauses and print each one immediately."""
    parsed: list[str] = []
    async for clause in clause_generator(
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
