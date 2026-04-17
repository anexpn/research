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
- `Success Criteria` (verifiable)
- `Constraints` (concrete)
- `Non-goals` (explicit boundaries)

Do not implement the feature in this skill.

## Clarification workflow

Copy this checklist each run:

```text
Clarify Progress:
- [ ] Restate current understanding in 1-3 bullets
- [ ] Ask one focused clarification question at a time (prefer AskQuestion tool)
- [ ] Integrate answers into a sharper draft
- [ ] Validate objective/success/constraints/non-goals are complete
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
- [ ] <Criterion 1: testable>
- [ ] <Criterion 2: testable>

## Constraints
- <Performance, style, dependency, safety, runtime constraints>

## Non-goals
- <Explicitly excluded work>

## Max Rounds
3
```

## Quality gates before writing

- No unresolved placeholders.
- Success criteria are testable and observable.
- Constraints are concrete enough to guide trade-offs.
- Non-goals are explicit and prevent scope creep.

## Interaction style

- Keep questions short and concrete.
- Ask one question per turn.
- Focus on one uncertainty cluster at a time.
- Avoid re-asking resolved details.
- Mark uncertainty explicitly (`unclear`, `assumed`, `conflicting`).
- When using `AskQuestion`, provide concrete answer options and include an "other / custom" option when useful.

