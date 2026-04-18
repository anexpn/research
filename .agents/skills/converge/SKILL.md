---
name: converge
description: Runs a high-integrity multi-agent converge loop with builder-inspector-judge roles and file-based evidence. Use when implementing non-trivial tasks that require verifiable completion, quality-gate enforcement, iterative deltas, or round-based orchestration.
---

# Converge

Use this skill to drive work from unsolved to verified completion with a deterministic loop.

## When to use

Use Converge when at least one is true:

- The task is complex enough to need iterative correction.
- "Done" must be backed by test or execution evidence.
- You need explicit quality review against standards.
- You want an auditable round-by-round history.

## Role model

- **Conductor**: creates session folders, enforces loop rules, launches role sub-agents, and stops on terminal states.
- **Builder**: implements changes and produces execution evidence.
- **Inspector**: checks Builder output against standards with evidence for each critique.
- **Judge**: resolves Builder vs Inspector using evidence and emits next-step delta.

## Conductor boundaries (non-negotiable)

1. Conductor is orchestration-only and must never perform Builder, Inspector, or Judge work directly.
2. Conductor must launch sub-agents for every Builder, Inspector, and Judge step in every round.
3. If a required sub-agent cannot be launched or completed, Conductor must stop with `BLOCKED`; it must not substitute by doing the role itself.
4. Conductor may run only orchestration helpers (for example, session/round setup scripts) and artifact routing tasks.

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
  round_1/
    builder_report.md
    inspector_review.md
    judge_resolution.md
  round_2/
    ...
```

## Operational guardrails

1. **Fresh context only**: for each new round, pass only `goal.md` and the previous round's `judge_resolution.md`.
2. **Fail fast**: any role can emit `blocker_detected: true`; Conductor exits immediately with blocker summary.
3. **Evidence first**: Builder and Inspector claims must include concrete evidence (test output, log snippets, diff references, or standards links).
4. **Judge must justify overruling**: if Inspector is overruled, Judge writes explicit reasoning and evidence.
5. **Round cap**: default max is `3` rounds unless user overrides.
6. **Human verification gate**: if any success criterion uses `verification_type: human` (or `mixed` with required human sign-off), `status: COMPLETE` is invalid until human evidence is recorded.
7. **Awaiting human is terminal for loop automation**: when human-gated criteria lack required evidence, Judge must emit `status: AWAITING_HUMAN` and Conductor must pause instead of continuing automated rounds.
8. **No placeholder evidence**: round artifacts must use concrete commands and artifact paths; placeholders like `<script here>` invalidate the round and require correction before the next role runs.

## Conductor workflow

Copy this checklist each run:

```text
Converge Progress:
- [ ] Read AGENTS.md and extract conventions
- [ ] Resolve session root and report naming
- [ ] Validate pre-existing goal.md has required fields
- [ ] Validate each success criterion includes verification type and expected evidence
- [ ] Run round 1 using sub-agents (Builder -> Inspector -> Judge)
- [ ] Evaluate Judge status
- [ ] If status is AWAITING_HUMAN, pause and request human verification evidence
- [ ] Continue rounds until COMPLETE, blocker, awaiting human, or max rounds
- [ ] Emit final summary for handoff or completion
```

### Step 1: Initialize session

Resolve session from `AGENTS.md`/user input and ensure `goal.md` already exists.

Validate `goal.md` includes at least:

- objective
- explicit success criteria
- for each criterion: `verification_type` (`automated|human|mixed`) and expected evidence
- constraints (if any)
- max rounds (or use default `3` if omitted)

If key fields are missing, stop and ask user to clarify instead of inferring.

Optional helper for creating session folders only (does not define the goal):

```bash
bash scripts/init_converge_session.sh "<short-task-slug>" "<session-root-from-agents-or-user>"
```

### Step 2: Run Builder

Conductor launches a Builder sub-agent with:

- `goal.md`
- previous `judge_resolution.md` (if round > 1)
- Builder system prompt in `prompts/builder_system_prompt.md`

Builder returns/writes the round's `builder_report.md`.

### Step 3: Run Inspector

Conductor launches an Inspector sub-agent with:

- `goal.md`
- current `builder_report.md`
- standards and references resolved from `AGENTS.md`
- Inspector system prompt in `prompts/inspector_system_prompt.md`

Inspector returns/writes the round's `inspector_review.md`.

### Step 4: Run Judge

Conductor launches a Judge sub-agent with:

- `goal.md`
- current `builder_report.md`
- current `inspector_review.md`
- Judge system prompt in `prompts/judge_system_prompt.md`

Judge returns/writes the round's `judge_resolution.md`.

### Step 5: Conductor decision

After each round:

1. If `blocker_detected: true`, stop and report blocker.
2. If `status: AWAITING_HUMAN`, stop automated looping and request human verification evidence before any next round.
3. If `status: COMPLETE`, stop and report verified completion.
4. If rounds reached max (`3`) and not complete, stop with graceful failure and handoff notes.
5. Else create next round and continue.

### Decision semantics (must stay consistent across templates and prompts)

- `status: CONTINUE`: criteria are not yet met, but the next action is still automatable via Builder.
- `status: AWAITING_HUMAN`: at least one human-gated criterion is still pending evidence; automation pauses for explicit human verification.
- `status: COMPLETE`: all criteria are satisfied and required evidence exists, including human evidence for any human-gated criteria.
- `blocker_detected: true`: hard external blocker or unsafe/indeterminate condition that prevents reliable continuation.

## Utility files

- Templates:
  - `templates/goal.template.md` (reference only; `goal.md` is expected to pre-exist)
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

- Final status: `COMPLETE`, `BLOCKED`, `AWAITING_HUMAN`, or `MAX_ROUNDS_REACHED`
- Evidence summary (tests, checks, or blocker proof)
- Remaining risks and exact next action (if not complete)

