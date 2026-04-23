This draft defines the **clarify** skill: a dialogue-first skill that converts an initial, vague request into a precise, actionable `goal.md` for downstream implementation skills.

---

## 1. Purpose

`clarify` exists to reduce failed implementations caused by ambiguous requirements.  
It helps the user discover and state:

- the real objective,
- measurable success criteria,
- constraints that must be respected,
- and explicit non-goals.

The output is a concise `goal.md` in a session folder resolved from `AGENTS.md`, ready for execution-oriented skills.

## 2. When To Use

Trigger `clarify` when a user request is underspecified, conflicting, or likely to hide assumptions.
Typical signals:

- broad asks ("make this better", "refactor this", "fix performance"),
- missing acceptance criteria,
- hidden trade-offs (speed vs. quality, new deps vs. no deps),
- no clear artifact definition.

## 3. Core Behavior

`clarify` runs an iterative Q&A loop with the user.

### 3.1 Clarification loop

1. Restate current understanding in 1-3 bullets.
2. Identify uncertainty and ask targeted questions (small batches, not a giant questionnaire).
3. Integrate user answers into a progressively sharper problem statement.
4. Repeat until the goal is clear enough to implement, or the user explicitly says to finalize.

### 3.2 Questions the skill must cover

The skill must collect, at minimum:

- **Objective:** What outcome should exist after completion?
- **Success criteria:** What artifacts prove completion? Which regressions must remain green? What new tests/checks should be added?
- **Constraints:** Performance expectations, style preferences, dependency limits, safety/security constraints, runtime/platform constraints.
- **Non-goals:** What should not be changed or attempted in this task?

### 3.3 Guidance behavior

When users are unsure, `clarify` should suggest common options and ask them to confirm, reject, or edit.
Example prompts:

- "Should success include updated tests and no new lints?"
- "Any restrictions on adding dependencies?"
- "Do you want to exclude refactors outside touched modules?"

## 4. Completion Criteria For Clarify Dialogue

`clarify` can finalize when either:

- required fields are sufficiently specific and internally consistent, or
- the user explicitly approves finalization with known uncertainty documented.

Before finalizing, `clarify` asks for explicit confirmation:
"Do you approve this goal draft?"

## 5. Output Contract

After approval, `clarify` writes `goal.md` using the goal template in the session folder defined by `AGENTS.md`:

- resolve session root and naming from `AGENTS.md` before writing,
- create the session folder if missing (following the resolved convention),
- keep wording concise and implementation-ready,
- include sections for Objective, Success Criteria, Constraints, and Non-goals.

Recommended quality checks before writing:

- no unresolved placeholders,
- success criteria are verifiable,
- non-goals are explicit,
- constraints are concrete enough to guide decisions.

## 6. Acceptance Checklist (Required Gates)

- Objective, success criteria, constraints, and non-goals are all explicitly captured.
- Output location is resolved from `AGENTS.md` and points to `<resolved-session-folder>/goal.md`.
- Human gives explicit binary approval: `approve` or `request changes`.

## 7. Suggested Interaction Style

- Keep questions short and concrete.
- Prefer one uncertainty cluster at a time.
- Avoid repeating already-settled details.
- Surface ambiguities explicitly ("unclear", "assumed", "conflicting").
- Preserve user language while tightening wording.

## 8. Non-Goals For This Skill

- Implementing the requested feature itself.
- Running large code changes or refactors.
- Replacing user decisions with autonomous assumptions.

---

This spec is intended to be consumed by the `create-skill` process to produce the actual `clarify` skill definition and prompts.