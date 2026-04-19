---
name: clarify
description: Converts vague user requests into implementation-ready goal and verification planning artifacts through iterative clarification. Use when requirements are underspecified, success criteria are missing, constraints conflict, or non-goals are unclear.
license: MIT
metadata:
  author: Jun <875241499@qq.com>
  version: "1.0.0"
---

# Clarify

Use this skill to convert ambiguous asks into implementation-ready planning artifacts.

## When to use

Use Clarify when objective, success criteria, constraints, or verification ownership are underspecified.

## Required outputs

1. `goal.md`
   - objective,
   - success criteria (each with `verification_type` + expected evidence),
   - constraints,
   - non-goals,
   - `max_implementation_rounds`,
   - `max_verification_rounds`.
2. `verification_spec.md`
   - criterion-level natural-language scenarios,
   - verification mode (`automated|agent|human|mixed`),
   - measurable automated pass conditions,
   - expected evidence and gate timing.

Do not implement product changes in this skill.

## Fast workflow

Use `templates/clarify_runbook.template.md` as the working checklist.

Ask one focused question at a time and iterate until requirements are precise enough for implementation.

Before writing files, use `AskQuestion` tool to require explicit approval:

`Do you approve this goal and verification draft? (approve/request changes)`

Proceed only on `approve`.

## File location and scaffolding

Resolve session path conventions from `AGENTS.md` before writing.

Write:

- `<resolved-session-folder>/goal.md`
- `<resolved-session-folder>/verification_spec.md`

Quick scaffold:

```bash
bash scripts/init_clarify_artifacts.sh "<resolved-session-folder>"
```

## Quality gates

- No placeholders or unresolved ambiguity without explicit note.
- Every criterion has `verification_type` and expected evidence.
- `verification_spec.md` maps all criterion ids from `goal.md`.
- Automated checks are falsifiable/measurable (not symbol-only or non-`None` checks).
- At least one regression-sensitive automated assertion per automated criterion.
- Subjective criteria include rubric and human evidence expectations.

## Utility files

- Runbook: `templates/clarify_runbook.template.md`
- Templates:
  - `templates/goal.template.md`
  - `templates/verification_spec.template.md`
- Script:
  - `scripts/init_clarify_artifacts.sh`

