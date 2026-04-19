# Converge Quickstart

Use this as the short operational checklist for each run.

## 1) Initialize

- Read `AGENTS.md` and resolve session path conventions.
- Ensure `goal.md` exists and includes:
  - objective,
  - explicit success criteria,
  - constraints/non-goals,
  - `max_implementation_rounds`,
  - `max_verification_rounds`.
- If present, ensure `verification_spec.md` maps criteria to checks.

## 2) Start or advance round

- New session: run `scripts/init_converge_session.sh`.
- Next round: run `scripts/new_round.sh`.
- Verify round has canonical files:
  - `builder_report.md`
  - `inspector_review.md`
  - `judge_resolution.md`
  - `run/`
- Pre-round sequencing gate:
  - If this is round 1 and `verification_spec.md` defines automated checks, set expected round intent to `build_verification_artifacts`.
  - Do not allow `implement_solution` until red-baseline verification evidence exists for open automated criteria.

## 3) Launch Judge

Pass `goal.md`, optional `verification_spec.md`, prior `judge_resolution.md` (if any), and standards references.

Judge must:

- delegate to exactly one Builder and one Inspector,
- orchestrate one round only,
- enforce canonical runtime artifact placement in `round_<n>/run/`,
- emit status using only `CONTINUE|READY_FOR_HUMAN|COMPLETE`,
- emit `blocker_detected: true` only for real hard blockers.
- record sequencing audit (verification-first required, baseline present, violation status) in `judge_resolution.md`.

## 4) Decide loop control

- Stop on `blocker_detected: true` -> `BLOCKED`.
- Stop on `READY_FOR_HUMAN` and request human evidence.
- Stop on `COMPLETE` when all required evidence exists.
- Stop on exhausted round caps -> `MAX_ROUNDS_REACHED`.
- Otherwise create next round and continue.