#!/usr/bin/env python3
# ABOUTME: Render Builder and Reviewer prompt files for the build-review-loop skill.
# ABOUTME: Fill bundled templates with the resolved design spec path and optional role requirements.

from __future__ import annotations

import argparse
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
PROMPTS_DIR = SKILL_DIR / "prompts"

DESIGN_SPEC_PLACEHOLDER = "{{DESIGN_SPEC_PATH}}"
ROLE_REQUIREMENTS_PLACEHOLDER = "{{ROLE_REQUIREMENTS_BLOCK}}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render Builder and Reviewer prompt files for build-review-loop."
    )
    parser.add_argument("design_spec", type=Path)
    parser.add_argument("--builder-output", type=Path)
    parser.add_argument("--reviewer-output", type=Path)
    parser.add_argument(
        "--builder-template",
        type=Path,
        default=PROMPTS_DIR / "builder_prompt.template.md",
    )
    parser.add_argument(
        "--reviewer-template",
        type=Path,
        default=PROMPTS_DIR / "reviewer_prompt.template.md",
    )
    parser.add_argument(
        "--builder-requirement",
        action="append",
        default=[],
        dest="builder_requirements",
    )
    parser.add_argument(
        "--reviewer-requirement",
        action="append",
        default=[],
        dest="reviewer_requirements",
    )
    return parser.parse_args()


def require_file(path: Path, *, label: str) -> Path:
    resolved = path.resolve()
    if not resolved.is_file():
        raise FileNotFoundError(f"{label} not found: {resolved}")
    return resolved


def render_role_requirements(requirements: list[str]) -> str:
    cleaned = [item.strip() for item in requirements if item.strip()]
    if not cleaned:
        return ""
    lines = ["Extra requirements:"]
    lines.extend(f"- {item}" for item in cleaned)
    return "\n".join(lines)


def render_prompt(
    template_path: Path,
    *,
    design_spec_path: Path,
    requirements: list[str],
) -> str:
    template_text = require_file(template_path, label="template").read_text(
        encoding="utf-8"
    )

    for placeholder in (DESIGN_SPEC_PLACEHOLDER, ROLE_REQUIREMENTS_PLACEHOLDER):
        if placeholder not in template_text:
            raise ValueError(f"Missing placeholder {placeholder!r} in {template_path}")

    prompt_text = template_text.replace(DESIGN_SPEC_PLACEHOLDER, str(design_spec_path))
    prompt_text = prompt_text.replace(
        ROLE_REQUIREMENTS_PLACEHOLDER, render_role_requirements(requirements)
    )

    while "\n\n\n" in prompt_text:
        prompt_text = prompt_text.replace("\n\n\n", "\n\n")

    if not prompt_text.endswith("\n"):
        prompt_text += "\n"

    return prompt_text


def write_prompt(output_path: Path, prompt_text: str) -> Path:
    resolved = output_path.resolve()
    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text(prompt_text, encoding="utf-8")
    return resolved


def default_builder_output_path(design_spec_path: Path) -> Path:
    return design_spec_path.parent / "build-review-loop.builder.prompt.md"


def default_reviewer_output_path(design_spec_path: Path) -> Path:
    return design_spec_path.parent / "build-review-loop.reviewer.prompt.md"


def main() -> int:
    args = parse_args()
    design_spec_path = require_file(args.design_spec, label="design spec")

    builder_prompt = render_prompt(
        args.builder_template,
        design_spec_path=design_spec_path,
        requirements=args.builder_requirements,
    )
    reviewer_prompt = render_prompt(
        args.reviewer_template,
        design_spec_path=design_spec_path,
        requirements=args.reviewer_requirements,
    )

    builder_output = write_prompt(
        args.builder_output or default_builder_output_path(design_spec_path),
        builder_prompt,
    )
    reviewer_output = write_prompt(
        args.reviewer_output or default_reviewer_output_path(design_spec_path),
        reviewer_prompt,
    )

    print(f"builder_prompt={builder_output}")
    print(f"reviewer_prompt={reviewer_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
