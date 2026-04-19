---
name: clarify
description: Converts vague user requests into implementation-ready goal and verification planning artifacts through iterative clarification. Use when requirements are underspecified, success criteria are missing, constraints conflict, or non-goals are unclear.
---

# Clarify

Use this skill to turn an ambiguous request into precise planning artifacts for downstream implementation skills.

## When to use

Apply Clarify when at least one is true:

- The ask is broad ("make this better", "refactor this", "improve performance").
- Acceptance criteria are missing or not testable.
- Constraints or trade-offs are implicit or conflicting.
- The expected output artifact is not clearly defined.

## Required outcome

Produce:

1. a concise `goal.md` that contains:

- `Objective`
- `Success Criteria` (verifiable with explicit verification type and evidence)
- `Constraints` (concrete)
- `Non-goals` (explicit boundaries)
- `Round Limits`:
  - `max_implementation_rounds`
  - `max_verification_rounds`

2. a `verification_spec.md` that contains criterion-level verification intent (no test code yet):

- BDD-like scenarios (`given/when/then`) in natural language
- verification mode per criterion: `automated|agent|human|mixed`
- for automated scenarios: explicit measurable pass conditions (comparator + threshold/tolerance/value)
- expected evidence artifacts
- gate timing (`per_round|final_only`)
- human guidance requirements when human verification is involved

Do not implement the feature in this skill.

## Clarification workflow

Copy this checklist each run:

```text
Clarify Progress:
- [ ] Restate current understanding in 1-3 bullets
- [ ] Ask one focused clarification question at a time (prefer AskQuestion tool)
- [ ] Integrate answers into a sharper draft
- [ ] Validate objective/success/constraints/non-goals are complete
- [ ] Validate round limits include separate implementation and verification caps
- [ ] Ensure each success criterion has verification_type and expected_evidence
- [ ] Draft criterion-level natural-language checks in verification_spec format
- [ ] For automated criteria, define scenario-level assertion contracts (not only feature presence)
- [ ] For subjective or taste-based criteria, define rubric and human verification evidence
- [ ] Ask for explicit approval to finalize
- [ ] Resolve session path from AGENTS.md
- [ ] Draft goal using templates/goal.template.md
- [ ] Draft verification spec using templates/verification_spec.template.md
- [ ] Write goal.md and verification_spec.md
```

### Step 1: Restate understanding

Start by summarizing the current request in 1-3 bullets using the user's wording where possible.

### Step 2: Ask targeted questions one-by-one

Ask exactly one clarification question at a time. Prioritize unresolved uncertainty only.

You must cover:

- **Objective**: what should be true after completion?
- **Success criteria**: what artifacts/checks prove done? what must stay green?
- **Automated assertion contract** (for each automated criterion): what exact behavior must fail on regression, and what numeric/bounded condition proves pass?
- **Verification ownership**: which criteria are `automated`, `agent`, `human`, or `mixed`?
- **Human gate evidence**: if any criterion needs human judgment, what evidence and approver identity are required?
- **Constraints**: performance, dependency, style, platform, security/safety limits.
- **Non-goals**: what must not be changed in this task?

Questioning method:

1. If an `AskQuestion` tool is available, use it.
2. Use one tool call per question (do not batch multiple questions in one call).
3. Wait for the user's answer before asking the next question.
4. If the tool is unavailable, ask conversationally, still one question at a time.

If the user is unsure, propose concrete options and ask them to confirm/reject/edit.

For automated criteria, ask toward executable precision:

- fixed fixture/input values to test,
- required output metric/property,
- oracle ownership (test-owned oracle/fixture vs implementation-provided helper),
- comparison operator (`==`, `<=`, `>=`, `within epsilon`, ordering),
- exact threshold/tolerance,
- determinism requirement (seed, stable scene, stable command),
- at least one regression trap (negative or contrasting case).

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

If an "automated" criterion cannot be expressed with falsifiable pass/fail conditions, do one of:

- downgrade that criterion to `agent` or `human` with an explicit rubric, or
- keep as `automated` only after adding measurable proxy checks and documenting limitations.

### Step 4: Require explicit approval

Before writing files, use `AskQuestion` tool to ask:

`Do you approve this goal and verification draft? (approve/request changes)`

Only proceed on explicit `approve`.

## Output location and file contract

Read `AGENTS.md` to resolve session conventions before writing.

Write:

`<resolved-session-folder>/goal.md`
`<resolved-session-folder>/verification_spec.md`

If `AGENTS.md` does not define enough path/naming detail, ask the user before creating folders.
If the target session folder does not exist, create it using the resolved convention.

## goal.md template

Use `templates/goal.template.md` as the default starting point.

Use `templates/verification_spec.template.md` for criterion-level verification intent.

You may adapt the wording, add criteria, or add sections, but do not remove required fields from "Required outcome".

When no human-gated criterion exists, set Human Verification fields to `none`/`false` rather than deleting the section.

## Quality gates before writing

- No unresolved placeholders.
- Success criteria are testable and observable.
- Every success criterion has `verification_type` and `expected_evidence`.
- `verification_spec.md` maps every criterion id in `goal.md`.
- `goal.md` defines both `max_implementation_rounds` and `max_verification_rounds` as positive integers.
- Every automated scenario includes at least one measurable pass condition (value, bound, tolerance, ordering, or deterministic artifact property).
- No automated scenario pass condition is only "no crash", "symbol exists", or "result is not None".
- At least one automated scenario per criterion includes a regression-sensitive assertion (negative/contrast/baseline comparison).
- Subjective criteria have an explicit rubric (not only "looks good" or "similar enough").
- Human-gated criteria define approver role and evidence format.
- Constraints are concrete enough to guide trade-offs.
- Non-goals are explicit and prevent scope creep.

## Converge handoff compatibility

To reduce low-value inspector loops in downstream Converge runs:

- Avoid unbounded taste-language in criteria; pair qualitative intent with concrete checks.
- If a criterion cannot be fully formalized, document the exact human decision gate up front.
- Write criteria so Inspector can produce actionable deltas instead of repeating ambiguity notes.

## Utility files

- Templates:
  - `templates/goal.template.md`
  - `templates/verification_spec.template.md`

## Interaction style

- Keep questions short and concrete.
- Ask one question per turn.
- Focus on one uncertainty cluster at a time.
- Avoid re-asking resolved details.
- Mark uncertainty explicitly (`unclear`, `assumed`, `conflicting`).
- When using `AskQuestion`, provide concrete answer options and include an "other / custom" option when useful.

