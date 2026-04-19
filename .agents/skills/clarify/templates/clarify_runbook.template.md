# Clarify Runbook

Use this as the short checklist while clarifying requirements.

## 1) Restate

- Summarize current understanding in 1-3 bullets.

## 2) Ask one focused question

Prioritize the highest-impact unknown:

- objective,
- success criteria,
- verification ownership (`automated|agent|human|mixed`),
- constraints,
- non-goals,
- round caps.

Ask exactly one question at a time. Prefer `AskQuestion` when available.

## 3) Tighten verification intent

For each criterion, ensure:

- explicit `verification_type`,
- expected evidence artifact,
- for automated checks: measurable pass condition (comparator + threshold/tolerance),
- at least one regression-sensitive assertion.

## 4) Confirm approval

Before writing files, ask:

`Do you approve this goal and verification draft? (approve/request changes)`

Proceed only on explicit `approve`.

## 5) Write artifacts

Use:

- `goal.md`
- `verification_spec.md`

Initialize quickly with:

```bash
bash scripts/init_clarify_artifacts.sh "<session-dir>"
```

