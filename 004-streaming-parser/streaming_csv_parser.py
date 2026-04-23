#!/usr/bin/env python3

"""Async streaming CSV parser demo using async generators.

Simulation details:
- chunks arrive every 0.5s
- background ticker prints every 0.25s
- consumer prints parsed lines as soon as complete
"""

from __future__ import annotations

import asyncio
from time import perf_counter
from typing import AsyncIterable, AsyncIterator


CHUNKS = ["id,n", "ame\n", "1,Jo", "e\n2,", "Sara", "h"]
EXPECTED_ROWS = ["id,name", "1,Joe", "2,Sarah"]
EXPECTED_CSV = "id,name\n1,Joe\n2,Sarah\n"


def elapsed(start: float) -> str:
    """Human-friendly elapsed timestamp."""
    return f"+{perf_counter() - start:0.2f}s"


async def simulated_chunk_stream(chunks: list[str], start: float) -> AsyncIterator[str]:
    """Simulate incoming chunks every 0.5s."""
    for chunk in chunks:
        await asyncio.sleep(0.5)
        print(f"{elapsed(start)} chunk arrived: {chunk!r}")
        yield chunk


async def async_csv_line_generator(chunk_stream: AsyncIterable[str]) -> AsyncIterator[str]:
    """Yield one CSV line at a time from an async chunk source."""
    pending = ""
    async for chunk in chunk_stream:
        pending += chunk
        while True:
            newline_index = pending.find("\n")
            if newline_index == -1:
                break
            yield pending[:newline_index]
            pending = pending[newline_index + 1 :]

    # Flush the final line if stream ends without trailing newline.
    if pending:
        yield pending


async def ticker(stop_event: asyncio.Event, start: float) -> None:
    """Background timer that prints every 0.25s."""
    while not stop_event.is_set():
        await asyncio.sleep(0.25)
        print(f"{elapsed(start)} tick")


async def consume_lines(start: float) -> tuple[list[str], str | None]:
    """Consume parsed lines and validate row emission order immediately."""
    lines: list[str] = []
    expected_idx = 0
    incoming_chunks = simulated_chunk_stream(CHUNKS, start)
    async for line in async_csv_line_generator(incoming_chunks):
        print(f"{elapsed(start)} line parsed: {line!r}")
        lines.append(line)

        if expected_idx >= len(EXPECTED_ROWS):
            return lines, f"Unexpected extra row: {line!r}"

        expected = EXPECTED_ROWS[expected_idx]
        if line != expected:
            return (
                lines,
                f"Row {expected_idx + 1} mismatch: expected {expected!r}, got {line!r}",
            )

        print(f"{elapsed(start)} row validated immediately")
        expected_idx += 1

    if expected_idx != len(EXPECTED_ROWS):
        return lines, f"Stream ended early: expected {len(EXPECTED_ROWS)} rows, got {expected_idx}"

    return lines, None


async def main() -> int:
    start = perf_counter()
    stop_event = asyncio.Event()
    ticker_task = asyncio.create_task(ticker(stop_event, start))

    lines, stream_error = await consume_lines(start)

    stop_event.set()
    await ticker_task

    actual_csv = "\n".join(lines) + "\n"
    expected_csv = EXPECTED_CSV

    if stream_error:
        print("Streaming row validation failed")
        print(stream_error)
        print("Rows parsed so far:")
        for row in lines:
            print(row)
        return 1

    if actual_csv == expected_csv:
        print("Stream parse OK (row-by-row + final CSV)")
        print(actual_csv)
        return 0

    print("Stream parse mismatch")
    print("Expected:")
    print(expected_csv)
    print("Actual:")
    print(actual_csv)
    return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
