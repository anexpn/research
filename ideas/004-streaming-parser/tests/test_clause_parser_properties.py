"""Property tests for streaming_clause_parser_configurable_parens.

Run with:
    pytest 004-streaming-parser/tests/test_clause_parser_properties.py
"""

from __future__ import annotations

import asyncio
import importlib.util
import sys
from pathlib import Path
from typing import AsyncIterator

from hypothesis import given
from hypothesis import strategies as st


PARSER_PATH = (
    Path(__file__).resolve().parents[1] / "streaming_clause_parser_configurable_parens.py"
)
SPEC = importlib.util.spec_from_file_location("clause_parser_module", PARSER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load parser module from {PARSER_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

ParseConfig = MODULE.ParseConfig
clause_generator = MODULE.clause_generator


async def _chunk_stream(chunks: list[str]) -> AsyncIterator[str]:
    for chunk in chunks:
        yield chunk


async def _parse_chunks(chunks: list[str], *, skip_wrapped: bool) -> list[str]:
    out: list[str] = []
    async for clause in clause_generator(
        _chunk_stream(chunks),
        config=ParseConfig(skip_wrapped=skip_wrapped),
    ):
        out.append(clause)
    return out


def _run(coro):
    return asyncio.run(coro)


def _cut_text_into_chunks(text: str, cuts: list[int]) -> list[str]:
    if not text:
        return [""]

    valid_cuts = sorted({c for c in cuts if 0 < c < len(text)})
    chunks: list[str] = []
    start = 0
    for cut in valid_cuts:
        chunks.append(text[start:cut])
        start = cut
    chunks.append(text[start:])
    return chunks


TEXT_ALPHABET = st.characters(
    blacklist_categories=("Cs",),
    blacklist_characters=("\n",),
)


@given(
    text=st.text(alphabet=TEXT_ALPHABET, min_size=0, max_size=200),
    cuts=st.lists(st.integers(min_value=0, max_value=220), min_size=0, max_size=40),
    skip_wrapped=st.booleans(),
)
def test_chunking_invariance(text: str, cuts: list[int], skip_wrapped: bool) -> None:
    """Any random chunking should match one-shot parsing output."""
    many_chunks = _cut_text_into_chunks(text, cuts)
    one_chunk = [text]

    out_many = _run(_parse_chunks(many_chunks, skip_wrapped=skip_wrapped))
    out_one = _run(_parse_chunks(one_chunk, skip_wrapped=skip_wrapped))

    assert out_many == out_one


@given(
    left=st.text(alphabet=TEXT_ALPHABET, min_size=0, max_size=40),
    right=st.text(alphabet=TEXT_ALPHABET, min_size=0, max_size=40),
    whole=st.integers(min_value=0, max_value=99999),
    frac=st.integers(min_value=0, max_value=99999),
)
def test_decimal_not_split_across_chunks(
    left: str, right: str, whole: int, frac: int
) -> None:
    """A decimal number like 3.14 should survive even hostile chunk boundaries."""
    decimal = f"{whole}.{frac}"
    text = f"{left} {decimal}, {right}."

    # Force boundary immediately after decimal dot.
    dot_index = text.index(".")
    chunks = [text[: dot_index + 1], text[dot_index + 1 :]]

    parsed = _run(_parse_chunks(chunks, skip_wrapped=False))
    joined = " | ".join(parsed)
    assert decimal in joined


@given(
    prefix=st.text(alphabet=TEXT_ALPHABET, min_size=0, max_size=40),
    tail_core=st.text(alphabet=TEXT_ALPHABET, min_size=1, max_size=50),
    opener=st.sampled_from(["(", "{"]),
)
def test_unclosed_wrapper_tail_recovered(
    prefix: str, tail_core: str, opener: str
) -> None:
    """Unclosed wrapper content at EOF should be emitted, not dropped."""
    # Ensure the generated case is truly "unclosed" for the selected opener.
    closer = ")" if opener == "(" else "}"
    tail = tail_core.replace(closer, "")
    if not tail:
        tail = "x"

    text = f"{prefix} {opener}{tail}"
    parsed = _run(_parse_chunks([text], skip_wrapped=True))

    assert parsed
    normalized_tail = " ".join(tail.split())
    assert any(normalized_tail in clause for clause in parsed)
