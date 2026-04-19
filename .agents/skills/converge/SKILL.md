---
name: converge
description: Runs a high-integrity multi-agent converge loop with judge-led orchestration, builder implementation, and inspector verification backed by round artifacts.
license: MIT
metadata:
  author: Jun <875241499@qq.com>
  version: "1.0.0"
---

# Converge

Use this skill to run a repeatable Judge -> Builder -> Inspector loop with auditable artifacts.

## When to use

Use Converge when you need iterative correction plus evidence-backed completion.

## Operating model

- **Conductor**: starts rounds and enforces terminal states.
- **Judge**: orchestrates one round only.
- **Builder**: implements and collects evidence.
- **Inspector**: verifies against criteria and standards.

## Non-negotiable boundaries

1. Conductor is orchestration-only; no direct Builder/Inspector/Judge substitution.
2. One Judge per round; only Conductor starts the next round.
3. If required sub-agents cannot run, stop with `BLOCKED`.
4. `round_<n>/run/` is canonical for runtime outputs.
5. Use only decision tokens: `CONTINUE|READY_FOR_HUMAN|COMPLETE` plus `blocker_detected`.

## Minimal file contract

Session layout:

```text
<session_root>/<session_id>/
  goal.md
  verification_spec.md   # optional but recommended
  round_<n>/
    builder_report.md
    inspector_review.md
    judge_resolution.md
    run/
```

Runtime outputs belong in `run/`. Verification/source code artifacts belong in normal project paths, with optional snapshots into `run/` when needed for immutable audit history.

## Fast workflow

Use `templates/conductor_quickstart.template.md` as the step-by-step run checklist.

Initialization and scaffolding:

```bash
bash scripts/init_converge_session.sh "<task-slug>" "<session-root>"
bash scripts/new_round.sh "<session-dir>"
```

Both scripts now auto-scaffold canonical round docs from templates.

## Judge launch contract

When launching Judge, pass:

- `goal.md`
- `verification_spec.md` (if present)
- prior `judge_resolution.md` (if round > 1)
- `standards/verification_strength.md`
- prompt: `prompts/judge_system_prompt.md`

Judge must:

1. delegate to exactly one Builder and one Inspector,
2. read required context before action,
3. close exactly one round,
4. enforce canonical artifact routing,
5. emit delegation receipts in `judge_resolution.md`.

Verification-first sequencing policy:

- If `verification_spec.md` exists and open criteria require automated checks, round 1 should default to `build_verification_artifacts`.
- Do not run `implement_solution` until verification artifacts exist and include red-baseline evidence (unmet-criterion checks fail for the expected reason).
- If a round violates this ordering, treat it as invalid for closure and force remediation deltas back to `build_verification_artifacts`.

If delegation receipts are missing/inconsistent, treat the round as invalid and stop with `BLOCKED`.

## Loop control

After each round:

1. `blocker_detected: true` -> `BLOCKED`
2. `status: READY_FOR_HUMAN` -> pause for human evidence
3. `status: COMPLETE` with all required evidence -> done
4. configured cap reached -> `MAX_ROUNDS_REACHED`
5. else create next round and continue

## Utility files

- Standards: `standards/verification_strength.md`
- Quick checklist: `templates/conductor_quickstart.template.md`
- Templates:
  - `templates/builder_report.template.md`
  - `templates/inspector_review.template.md`
  - `templates/judge_resolution.template.md`
  - `templates/human_verification.template.md`
- Prompts:
  - `prompts/builder_system_prompt.md`
  - `prompts/inspector_system_prompt.md`
  - `prompts/judge_system_prompt.md`
- Scripts:
  - `scripts/init_converge_session.sh`
  - `scripts/new_round.sh`
  - `scripts/scaffold_round.sh`
