from __future__ import annotations

import subprocess
import sys
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parent.parent
SCRIPT_PATH = SKILL_DIR / "scripts" / "render_prompts.py"


def run_render_prompts(
    tmp_path: Path,
    *,
    builder_requirements: list[str] | None = None,
    reviewer_requirements: list[str] | None = None,
) -> tuple[subprocess.CompletedProcess[str], Path, Path, Path]:
    brief_path = tmp_path / "build-brief.md"
    brief_path.write_text("# Build brief\n", encoding="utf-8")

    builder_output = tmp_path / "builder.prompt.md"
    reviewer_output = tmp_path / "reviewer.prompt.md"

    command = [
        sys.executable,
        str(SCRIPT_PATH),
        "--build-brief",
        str(brief_path),
        "--builder-output",
        str(builder_output),
        "--reviewer-output",
        str(reviewer_output),
    ]

    for requirement in builder_requirements or []:
        command.extend(["--builder-requirement", requirement])
    for requirement in reviewer_requirements or []:
        command.extend(["--reviewer-requirement", requirement])

    result = subprocess.run(command, capture_output=True, text=True, check=False)
    return result, brief_path, builder_output, reviewer_output


def test_render_prompts_renders_both_files_with_role_requirements(tmp_path: Path) -> None:
    result, brief_path, builder_output, reviewer_output = run_render_prompts(
        tmp_path,
        builder_requirements=["Keep diffs local", "Run targeted verification"],
        reviewer_requirements=["Block on missing verification evidence"],
    )

    assert result.returncode == 0, result.stderr

    builder_text = builder_output.read_text(encoding="utf-8")
    reviewer_text = reviewer_output.read_text(encoding="utf-8")

    assert str(brief_path.resolve()) in builder_text
    assert str(brief_path.resolve()) in reviewer_text
    assert "Extra requirements:" in builder_text
    assert "- Keep diffs local" in builder_text
    assert "- Run targeted verification" in builder_text
    assert "Extra requirements:" in reviewer_text
    assert "- Block on missing verification evidence" in reviewer_text


def test_render_prompts_omits_extra_requirements_block_when_none_are_set(tmp_path: Path) -> None:
    result, brief_path, builder_output, reviewer_output = run_render_prompts(tmp_path)

    assert result.returncode == 0, result.stderr

    builder_text = builder_output.read_text(encoding="utf-8")
    reviewer_text = reviewer_output.read_text(encoding="utf-8")

    assert str(brief_path.resolve()) in builder_text
    assert str(brief_path.resolve()) in reviewer_text
    assert "Extra requirements:" not in builder_text
    assert "Extra requirements:" not in reviewer_text


def test_render_prompts_builder_frames_brief_as_implementation_input(tmp_path: Path) -> None:
    result, brief_path, builder_output, _ = run_render_prompts(tmp_path)

    assert result.returncode == 0, result.stderr

    builder_text = builder_output.read_text(encoding="utf-8")

    assert f"Implementation brief: `{brief_path.resolve()}`" in builder_text
    assert "not as the artifact to rewrite" in builder_text
    assert "unless the brief explicitly asks for its own update." in builder_text
