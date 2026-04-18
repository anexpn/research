---
name: clarify
description: Converts vague user requests into an implementation-ready goal.md through an iterative clarification dialogue. Use when requirements are underspecified, success criteria are missing, constraints conflict, or non-goals are unclear.
---

# Clarify

Use this skill to turn an ambiguous request into a precise `goal.md` for downstream implementation skills.

## When to use

Apply Clarify when at least one is true:

- The ask is broad ("make this better", "refactor this", "improve performance").
- Acceptance criteria are missing or not testable.
- Constraints or trade-offs are implicit or conflicting.
- The expected output artifact is not clearly defined.

## Required outcome

Produce a concise `goal.md` that contains:

- `Objective`
- `Success Criteria` (verifiable with explicit verification type and evidence)
- `Constraints` (concrete)
- `Non-goals` (explicit boundaries)
- `Max Rounds`

Do not implement the feature in this skill.

## Clarification workflow

Copy this checklist each run:

```text
Clarify Progress:
- [ ] Restate current understanding in 1-3 bullets
- [ ] Ask one focused clarification question at a time (prefer AskQuestion tool)
- [ ] Integrate answers into a sharper draft
- [ ] Validate objective/success/constraints/non-goals are complete
- [ ] Ensure each success criterion has verification_type and expected_evidence
- [ ] For subjective or taste-based criteria, define rubric and human verification evidence
- [ ] Ask for explicit approval to finalize
- [ ] Resolve session path from AGENTS.md
- [ ] Write goal.md
```

### Step 1: Restate understanding

Start by summarizing the current request in 1-3 bullets using the user's wording where possible.

### Step 2: Ask targeted questions one-by-one

Ask exactly one clarification question at a time. Prioritize unresolved uncertainty only.

You must cover:

- **Objective**: what should be true after completion?
- **Success criteria**: what artifacts/checks prove done? what must stay green?
- **Verification ownership**: which criteria are `automated`, `human`, or `mixed`?
- **Human gate evidence**: if any criterion needs human judgment, what evidence and approver identity are required?
- **Constraints**: performance, dependency, style, platform, security/safety limits.
- **Non-goals**: what must not be changed in this task?

Questioning method:

1. If an `AskQuestion` tool is available, use it.
2. Use one tool call per question (do not batch multiple questions in one call).
3. Wait for the user's answer before asking the next question.
4. If the tool is unavailable, ask conversationally, still one question at a time.

If the user is unsure, propose concrete options and ask them to confirm/reject/edit.

### Step 3: Iterate until clear enough

Repeat:

1. restate updated draft,
2. ask only the next highest-priority open question,
3. integrate answers.

Stop when all required fields are specific enough to guide implementation, or when the user asks to finalize with documented uncertainty.

If criteria remain vague after targeted questions, convert vagueness into explicit artifacts in `goal.md`:

- a measurable proxy check, or
- a written rubric for human evaluation, and
- a named follow-up clarification item.

### Step 4: Require explicit approval

Before writing files, ask:

`Do you approve this goal draft? (approve/request changes)`

Only proceed on explicit `approve`.

## Output location and file contract

Read `AGENTS.md` to resolve session conventions before writing.

Write:

`<resolved-session-folder>/goal.md`

If `AGENTS.md` does not define enough path/naming detail, ask the user before creating folders.
If the target session folder does not exist, create it using the resolved convention.

## goal.md template

Use this structure:

```markdown
# Goal

## Objective
<One immutable objective statement>

## Success Criteria
- [ ] id: C1
  - criterion: <Testable statement>
  - verification_type: <automated|human|mixed>
  - expected_evidence: <test output, artifact path, or reviewer sign-off>
  - rubric: <required when criterion is subjective or human-judged; else none>
- [ ] id: C2
  - criterion: <Testable statement>
  - verification_type: <automated|human|mixed>
  - expected_evidence: <test output, artifact path, or reviewer sign-off>
  - rubric: <required when criterion is subjective or human-judged; else none>

## Constraints
- <Performance, style, dependency, safety, runtime constraints>

## Non-goals
- <Explicitly excluded work>

## Max Rounds
3
```

When any criterion has `verification_type: human` (or `mixed` with human sign-off), add:

```markdown
## Human Verification
- required: true
- approver_role: <requester|reviewer|domain expert>
- evidence_format: <artifact links, screenshots, checklist, notes>
```

## Quality gates before writing

- No unresolved placeholders.
- Success criteria are testable and observable.
- Every success criterion has `verification_type` and `expected_evidence`.
- Subjective criteria have an explicit rubric (not only "looks good" or "similar enough").
- Human-gated criteria define approver role and evidence format.
- Constraints are concrete enough to guide trade-offs.
- Non-goals are explicit and prevent scope creep.

## Converge handoff compatibility

To reduce low-value inspector loops in downstream Converge runs:

- Avoid unbounded taste-language in criteria; pair qualitative intent with concrete checks.
- If a criterion cannot be fully formalized, document the exact human decision gate up front.
- Write criteria so Inspector can produce actionable deltas instead of repeating ambiguity notes.

## Interaction style

- Keep questions short and concrete.
- Ask one question per turn.
- Focus on one uncertainty cluster at a time.
- Avoid re-asking resolved details.
- Mark uncertainty explicitly (`unclear`, `assumed`, `conflicting`).
- When using `AskQuestion`, provide concrete answer options and include an "other / custom" option when useful.

