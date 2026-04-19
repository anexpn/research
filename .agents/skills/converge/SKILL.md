---
name: converge
description: Runs a high-integrity multi-agent converge loop with judge-led orchestration, builder implementation, and inspector verification backed by round artifacts.
---

# Converge

Use this skill to drive work from unsolved to verified completion with one consistent round loop.

## When to use

Use Converge when at least one is true:

- The task is complex enough to need iterative correction.
- "Done" must be backed by test or execution evidence.
- You need explicit quality review against standards.
- You want an auditable round-by-round history.

## Role model

- **Conductor**: outer-loop controller. Starts each round by launching Judge and enforces terminal states.
- **Judge**: round orchestrator. Determines round intent, launches Builder and Inspector, and resolves round status.
- **Builder**: implements the Judge delta and produces execution evidence.
- **Inspector**: validates Builder output against round intent, goal criteria, and standards with evidence-backed findings.

## Conductor boundaries (non-negotiable)

1. Conductor is orchestration-only and must never perform Builder, Inspector, or Judge work directly.
2. Conductor launches one Judge sub-agent per round; Judge manages Builder and Inspector for that round.
3. Conductor is the only role that may start another round or launch another Judge.
4. If a required sub-agent cannot be launched or completed, stop with `BLOCKED`; no role substitution.
5. Conductor may run only orchestration helpers (for example, session/round setup scripts) and artifact routing tasks.
6. Conductor must enforce source-of-truth token parsing rules from canonical round files.

## Required file protocol

### Project-level conventions

`AGENTS.md` is the source of truth for:

- Standards and reference locations
- Naming conventions for reports
- Session root location (if any)
- Any repository-specific constraints

If `AGENTS.md` is missing or incomplete, Conductor asks the user before assuming structure.

### Session-level history (per task)

Keep a per-round history, but do not hardcode folder roots. Conductor resolves the location from `AGENTS.md` or user input.

Use this logical layout:

```text
<session_root>/<session_id>/
  goal.md
  verification_spec.md
  round_1/
    builder_report.md
    inspector_review.md
    judge_resolution.md
    evidence/
  round_2/
    ...
```

`round_<n>/evidence/` is the canonical storage location for round evidence artifacts (for example rendered images, exported logs, screenshots, profiling output, or generated reports).

`round_<n>/` root should contain only canonical round documents:

- `builder_report.md`
- `inspector_review.md`
- `judge_resolution.md`
- `evidence/`

Do not keep duplicate evidence files in both `round_<n>/` and `round_<n>/evidence/`. If a command emits artifacts outside `evidence/`, move them into `evidence/` and cite the canonical evidence path.

`verification_spec.md` is recommended and should define criterion-level verification intent for:

- automated checks (tests/scripts),
- agent checks (prompted multimodal/text evaluation),
- human checks (guidance/checklist and sign-off expectations).

## Operational guardrails

1. **Required carry-forward context**: for each new round, pass `goal.md`, previous `judge_resolution.md`, and `verification_spec.md` when present.
   - Judge should emit a structured carry-forward bundle inside `judge_resolution.md`.
   - Keep a small required core:
     - `open_criteria`: unmet criterion ids with failure reason and evidence path
     - `ordered_delta_backlog`: priority-ordered Builder actions with stop conditions
   - Add these when useful (recommended, not mandatory):
     - `locked_scope`, `do_not_touch`, `accepted_evidence_reuse`, `invalidated_evidence`, `risk_watchlist`, `environment_notes`
2. **One loop type**: every round uses the same Judge-led flow (Judge plans -> Builder executes -> Inspector verifies -> Judge resolves); only round intent changes.
3. **Judge is single-round only**: Judge must orchestrate exactly one round and then stop. Judge must never launch another Judge, create a new round folder, or run multi-round loops.
4. **Intent-driven rounds**: Judge sets `round_intent` explicitly (for example `build_verification_artifacts`, `implement_solution`, `final_gate`).
5. **Evidence first**: Builder and Inspector claims must include concrete evidence (test output, log snippets, diff references, artifact paths).
6. **Canonical artifact location**: generated round artifacts must be written directly to `round_<n>/evidence/` when possible; otherwise move them there and remove redundant copies.
7. **Selective evidence snapshotting**: copy stable source artifacts (tests/prompts/checklists/specs) into round evidence only when they changed this round or are otherwise required for immutable audit snapshots.
8. **Artifact provenance**: for each moved or copied artifact, record original source path and canonical evidence path.
9. **Judge must justify overruling**: if Inspector is overruled, Judge writes explicit reasoning and evidence.
10. **Verification strength standard**: apply `standards/verification_strength.md` for verification-spec quality, automated assertion strength, and enforcement expectations.
11. **Automated assertion strength bar**: tests must satisfy the behavioral assertion requirements in `standards/verification_strength.md`; symbol-presence or non-`None` checks alone are insufficient unless explicitly justified.
12. **Round caps**: use separate limits from `goal.md`:
   - `max_verification_rounds` applies to rounds with `round_intent: build_verification_artifacts`.
   - `max_implementation_rounds` applies to rounds with `round_intent: implement_solution`.
   - `final_gate` rounds do not consume either cap unless `goal.md` explicitly says otherwise.
13. **No placeholder evidence**: concrete commands and artifact paths are required; placeholders invalidate the round.
14. **Source-of-truth tokens only**: criterion status must be parsed from explicit token fields in canonical files, never inferred from prose.
15. **Human verification timing default**: `final_only` unless `goal.md` or `verification_spec.md` says otherwise.

## Conductor workflow

Copy this checklist each run:

```text
Converge Progress:
- [ ] Read AGENTS.md and extract conventions
- [ ] Resolve session root and report naming
- [ ] Validate pre-existing goal.md has required fields
- [ ] Validate verification metadata in goal.md and/or verification_spec.md
- [ ] Launch Judge for round 1
- [ ] Evaluate Judge status
- [ ] If status is READY_FOR_HUMAN, request human verification evidence
- [ ] Continue rounds until COMPLETE, BLOCKED, READY_FOR_HUMAN, or either configured round cap is reached
- [ ] Emit final summary for handoff or completion
```

### Step 1: Initialize session

Resolve session from `AGENTS.md`/user input and ensure `goal.md` already exists.

- Do not require `goal.md` to match any specific template or heading names.
- Accept any structure (bullets, prose, tables, custom sections) if required information is unambiguous.
- If wording is ambiguous, ask for clarification instead of forcing a rewrite.

Validate `goal.md` includes at least:

- objective
- explicit success criteria
- for each criterion: `verification_type` (`automated|agent|human|mixed`) and expected evidence
- constraints (if any)
- `max_implementation_rounds`
- `max_verification_rounds`

If `verification_spec.md` exists, validate it maps each criterion to intended checks.
Validation must also enforce `standards/verification_strength.md` so each automated scenario has explicit, measurable pass/fail expectations.
If either round cap is missing, stop and ask user to clarify instead of inferring.
If key fields are missing, stop and ask user to clarify instead of inferring.

Optional helper for creating session folders only (does not define the goal):

```bash
bash scripts/init_converge_session.sh "<short-task-slug>" "<session-root-from-agents-or-user>"
```

### Step 2: Judge orchestrates the round

Conductor launches Judge with:

- `goal.md`
- `verification_spec.md` (if present)
- previous `judge_resolution.md` (if round > 1)
- standards and references resolved from `AGENTS.md`
- Judge system prompt in `prompts/judge_system_prompt.md`

Judge responsibilities for every round:

1. determine `round_intent`,
2. prepare explicit Builder input and output requirements,
3. launch Builder sub-agent,
4. prepare explicit Inspector scope,
5. launch Inspector sub-agent,
6. resolve status in `judge_resolution.md`,
7. update round memory inside `judge_resolution.md` (locked strengths, detected regressions, and next priority deltas).

Judge must stop after writing the current round's `judge_resolution.md`. Starting additional rounds is Conductor-only.

Judge-to-next-Builder handoff guideline:

- Judge should make next-round Builder input executable without re-deriving intent from prose.
- `delta_instructions` should reference `ordered_delta_backlog` ids when available.
- If Inspector reports unresolved ambiguity, Judge must either:
  - convert it into a concrete Builder-safe instruction, or
  - mark it as `needs_user_clarification` and block continuation on that criterion.

### Step 3: Intent-specific expectations (same loop, different purpose)

For `round_intent: build_verification_artifacts`:

- Builder creates missing verification artifacts as task deliverables:
  - automated checks: tests/scripts (code),
  - agent checks: prompt artifacts and expected output schema/rubric,
  - human checks: guidance text/checklist for human sign-off.
- Inspector verifies artifact quality and criterion coverage.
- Builder writes produced verification artifacts directly into `round_<n>/evidence/` when possible, and records source->canonical path mappings.

Within `round_intent: build_verification_artifacts`, Inspector must also enforce the red baseline:

- Builder executes verification against current implementation baseline for newly created checks.
- Inspector confirms unmet-criterion checks fail as expected for the right reason.

For `round_intent: implement_solution`:

- Builder implements product changes and updates evidence.
- Builder keeps newly produced verification artifacts canonically in `round_<n>/evidence/` (no duplicate same-name files in round root).
- Inspector confirms criteria closure and non-regression.

For `round_intent: final_gate`:

- Builder/Inspector ensure required agent and human evidence artifacts are present and valid.
- Required evidence artifacts must exist in `round_<n>/evidence/` (or be copied there before final decision).

### Step 4: Conductor decision

After each round:

1. If `blocker_detected: true`, stop and report blocker.
2. If `status: READY_FOR_HUMAN`, stop automated looping and request human verification evidence.
3. If required human evidence is provided and valid, finalize as `COMPLETE`.
4. If `status: COMPLETE` (no pending human gate), stop and report verified completion.
5. If either configured round cap is reached and not complete, stop with `MAX_ROUNDS_REACHED` and include which cap was exhausted plus remaining open criteria.
6. Else create next round and continue.

### Decision semantics (must stay consistent across templates and prompts)

- `status: CONTINUE`: criteria are not yet met, and next action is automatable via Builder.
- `status: READY_FOR_HUMAN`: all automatable checks are satisfied and required human evidence is now needed.
- `status: COMPLETE`: all required criteria are satisfied and required evidence exists, including human evidence when applicable.
- `blocker_detected: true`: hard external blocker or unsafe/indeterminate condition prevents reliable continuation.

## Utility files

- Standards:
  - `standards/verification_strength.md`
- Templates:
  - `templates/builder_report.template.md`
  - `templates/inspector_review.template.md`
  - `templates/judge_resolution.template.md`
  - `templates/human_verification.template.md`
- Role prompts:
  - `prompts/builder_system_prompt.md`
  - `prompts/inspector_system_prompt.md`
  - `prompts/judge_system_prompt.md`
- Scripts:
  - `scripts/init_converge_session.sh` - create session and `round_1` at a chosen root.
  - `scripts/new_round.sh` - create the next round folder in a session.

## Output contract

At the end, Conductor must produce one concise result:

- Final status: `COMPLETE`, `BLOCKED`, `READY_FOR_HUMAN`, or `MAX_ROUNDS_REACHED`
- If max reached: identify `implementation` or `verification` cap exhaustion explicitly
- Evidence summary (tests, checks, prompts, human sign-off, or blocker proof)
- Remaining risks and exact next action (if not complete)
