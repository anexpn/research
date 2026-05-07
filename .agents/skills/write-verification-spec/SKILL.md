---
name: write-verification-spec
description: Use when Human asks Codex to turn a design doc, behavior description, workflow, API contract, bug report, or existing verification draft into a Markdown verification spec with compliant Subject, Observation, Pattern, and Statement sections.
---

# Write Verification Spec

Treat the reference below as the working rules for drafting and revising verification specs.

## What This Skill Produces

This skill produces a Markdown verification spec written in controlled natural language.

Use it for functional behavior that can be checked automatically.

Do not use it for:

- non-automatable acceptance criteria;
- non-functional requirements as first-class items;
- framework-specific test plans;
- schema design for YAML, JSON, or other machine-authoring formats;
- coverage targets or mutation-testing policies.

## Core Model

The unit of thought is a verification item, not a test case and not a schema record.

Each verification item has four parts:

- `Subject`: the externally meaningful thing whose behavior is being constrained.
- `Observation`: where that behavior is observed.
- `Pattern`: the statement shape that best matches the obligation.
- `Statement`: what behavior must be true.

`Subject` should name the narrowest externally meaningful thing that carries the obligation. Prefer domain subjects such as `publish lifecycle`, `lambertian material response`, `foreground silhouette anti-aliasing behavior`, or `CLI render invocation`.

`Observation` should name the externally visible surface or measurement surface where the subject is checked. Prefer observations such as `listing responses`, `stored document status`, `stderr error text`, `output image dimensions`, or `pixel variance in the designated edge band`.

Organize verification items by contract: a coherent area of externally observable behavior such as a publish lifecycle, parser contract, selection model, sync protocol, or render invocation contract.

## Statement Patterns

Use only these three patterns:

- `Scenario`
  Form: `Given <context>, when <action>, then <observable outcome>.`
  Use for concrete scenarios, regressions, and named edge cases.
- `Property`
  Form: `For any <input domain or context>, if <precondition or trigger>, then <observable property>.`
  Use for general correctness over a domain, named partitions, workflow transitions, invariants, rejection behavior, and equivalence claims.
- `Progress`
  Form: `From <state or trigger>, <outcome> eventually becomes true [within <bound>].`
  Use for eventual completion, delivery, convergence, and bounded asynchronous behavior.

## Pattern Boundaries

- `Boundary` is not a top-level pattern. Express boundary behavior inside `Scenario` or `Property`.
- Given-When-Then is useful only as the `Scenario` pattern. It is not the whole language.
- Treat transition-shaped, invariant-shaped, and equivalence-shaped obligations as tighter `Property` statements.
- `Property test`, `table test`, and `mutation test` are verifier techniques, not behavior statement primitives.

## Authoring Rules

Every verification item must satisfy all of these rules:

- `External`: state observable behavior, not internals. Prefer visible state, returned values, persisted outcomes, emitted responses, externally visible errors, output artifacts, and named observation regions. Avoid helper names, private data structures, mocks, call counts, and storage details that are not part of the public contract.
- `Anchored`: name the subject and observation explicitly. Avoid hidden generic subjects such as `the system`, `the feature`, or `the render` when a narrower subject exists.
- `Singular`: state one obligation at a time. If two outcomes can fail independently, split them.
- `Scoped`: name the relevant context, state, input domain, or operation family explicitly.
- `Quantified`: use explicit quantification when it matters, such as `for any`, `for every`, `there exists`, `never`, `only if`, or `exactly once`.
- `Complete`: the statement must say enough to derive the intended verification strategy. If sequence behavior, rejection behavior, equivalence, or a bound matters, say so in the statement instead of outsourcing it to a separate note. A good `Property` statement should usually be enough to derive a property test directly.
- `Falsifiable`: a reader should be able to imagine a concrete counterexample.
- `Implementation-agnostic`: describe the contract without depending on code structure, unless an implementation detail is itself part of the externally visible behavior.
- `Domain-language`: prefer product or problem-domain terms over module, framework, or pattern language.

Quick check for every item:

- what subject is being constrained?
- where is that subject observed?
- under what conditions?
- over what action, event, state change, or input family?
- what observable result must hold?
- what important variation must also be true, if any, such as rejection, sequence behavior, equivalence, or bounds?
- what would count as failure?

## Rejection Rules

Reject and rewrite:

- vague claims such as `works correctly`, `handles edge cases`, or `stays in sync`;
- statements with missing subject, missing observation surface, missing scope, or missing observable outcome;
- statements that combine multiple independently failing obligations;
- statements framed mainly in terms of implementation details;
- `Property` statements with an implicit domain, trigger, or observable result;
- statements that leave important variation implicit when that variation changes what must be verified, such as rejection behavior, sequence behavior, equivalence, or bounds;
- statements that rely on a separate note to supply behavior that should have been stated as part of the obligation.

Weak statements such as these are non-compliant:

- `Publishing works correctly.`
- `The parser handles edge cases.`
- `The UI keeps state in sync.`
- `The render looks correct.`

Rewrite them into precise statements such as:

- `For any document in Draft, if Publish is invoked, then stored status becomes Published and listing visibility becomes true.`
- `For any document already in Published, if Publish is invoked, then the invocation is rejected and stored status remains Published.`
- `For any valid token stream, parsing consumes the entire stream or reports the first unconsumed position.`
- `For any selected-item removal from a non-empty visible selection, the visible selection moves to the next visible item, or becomes empty if none remain.`
- `Given the canonical spheres scene, when rendered at 1 sample per pixel and at N samples per pixel, the higher-sample render has lower variance in the designated silhouette edge band.`

## Item Shape

Each contract should contain one or more verification items with this shape:

```md
## Contract: <contract name>

### <short item name>

Subject
<externally meaningful subject>

Observation
<observation surface>

Pattern
<Scenario | Property | Progress>

Statement
<controlled natural-language verification statement>
```

Stable identifiers may be added when helpful, but they are optional. Headings should remain readable as normal language.

## Example Spec

```md
# Document Publish Verification Spec

## Scope
This spec covers the functional correctness of publishing a document.

## Contract: Publish lifecycle

### Publish changes status and visibility
Subject
Document publish lifecycle

Observation
Stored document status and listing responses

Pattern
Property

Statement
For any document in Draft, if Publish is invoked, then stored status becomes Published and listing visibility becomes true.

### Repeated publish is rejected
Subject
Document publish command acceptance

Observation
Publish command result and stored document status

Pattern
Property

Statement
For any document already in Published, if Publish is invoked, then the invocation is rejected and stored status remains Published.

### Publish preserves body content
Subject
Published document body content

Observation
Stored document body in subsequent read responses

Pattern
Property

Statement
For any published document, after any sequence of read and list operations, the stored body content remains unchanged.

### Publish becomes visible within one indexing cycle
Subject
Published document listing visibility

Observation
Listing responses

Pattern
Progress

Statement
From Published, listing visibility eventually becomes true within one indexing cycle.

### API and UI publish are equivalent
Subject
Publish entry-point behavior

Observation
Stored status and listing visibility

Pattern
Property

Statement
For any publishable draft, if the draft is published through the API and through the UI, then the stored status and listing visibility are the same.
```

## Workflow

1. Extract externally observable behavior and candidate subjects.
   Ignore implementation details unless they are themselves externally visible.
   Ignore non-functional requirements and non-automatable acceptance criteria.
   If the source mixes multiple features, split them into separate contracts.
   For each obligation, name the narrowest externally meaningful subject and the observation surface where it is checked.
2. Define contracts before items.
   Group behavior by coherent external contracts such as a publish lifecycle, parser contract, selection model, sync protocol, or render invocation contract.
   Name each contract in domain language.
3. Choose the narrowest statement pattern.
   Use `Scenario` for a concrete scenario, regression, or named edge case.
   Use `Progress` for eventual completion, convergence, delivery, or bounded asynchronous behavior.
   Use `Property` for quantified correctness claims over inputs, states, workflows, sequences, rejection behavior, or paired executions.
   Express transition-shaped, invariant-shaped, and equivalence-shaped obligations as tightly scoped `Property` statements instead of separate patterns.
4. Write one obligation per item.
   Fill in `Subject`, `Observation`, `Pattern`, and `Statement`.
   Make context, action or input family, and observable outcome explicit.
   Use quantifiers when the claim is broad, such as `for any`, `never`, `only if`, or `exactly once`.
   If sequence behavior, rejection behavior, equivalence, or a bound matters, state it directly instead of implying it.
   If two outcomes can fail independently, split them into separate items.
   Prefer domain terms over module, framework, or test-tool terms.
   Ask what concrete counterexample would falsify the statement and rewrite until the failure is obvious.
5. Assemble the spec in Markdown.
   Use readable headings.
   Add `## Scope` when the boundary needs to be explicit.
   Follow the item shape above exactly.
6. Review the written spec point by point before delivering it.
   Re-read every contract and every verification item in order.
   Check `Completeness`: the source's externally observable obligations are covered or explicitly called out as assumptions or open questions; each item has `Subject`, `Observation`, `Pattern`, and `Statement`; implied rejection or edge-case obligations are not silently omitted.
   Check `Effectiveness`: the named subject and observation are specific enough; the chosen pattern is the narrowest fit; the statement satisfies the authoring rules; and the statement is complete enough to derive an adequate verification strategy.
   If a point fails either check, rewrite the spec inline before delivering it and mention any remaining ambiguity explicitly.

## Writing Checks

- Reject vague claims such as `works correctly`, `handles edge cases`, or `stays in sync`.
- Reject items with missing subject, missing observation, missing scope, or missing observable outcome.
- Reject hidden generic subjects when a narrower externally meaningful subject exists.
- Reject `Property` items that should really be `Progress` or `Scenario`.
- Reject weak `Property` items that fail to make transition-shaped, invariant-shaped, rejection-shaped, or equivalence-shaped obligations explicit in the statement.
- Reject compound obligations that should be split.
- Reject items that depend on a separate note to explain the real obligation.
- If the source artifact leaves behavior ambiguous, surface the gap as an open question or explicit assumption instead of inventing details.
- After the draft is written, review every contract and item point by point for `Completeness` and `Effectiveness`.
- `Completeness` asks whether the spec covers the source's externally observable obligations with compliant item shape and whether any meaningful omission is called out explicitly.
- `Effectiveness` asks whether each item's subject, observation, pattern, and statement actually support verification of the claimed behavior with enough strength to catch realistic failures.

## Output Shape

Use this skeleton unless Human asked for a different surrounding format:

```md
## Contract: <contract name>

### <short item name>

Subject
<externally meaningful subject>

Observation
<observation surface>

Pattern
<Scenario | Property | Progress>

Statement
<controlled natural-language verification statement>
```

## Delivery

When drafting from source material:

- Produce the verification spec first.
- Review the written spec point by point for completeness and effectiveness, and fold any fixes back into the spec before finalizing.
- Put unresolved ambiguities or assumptions after the spec.

When revising an existing verification spec:

- Point out non-compliant items directly.
- Rewrite them into compliant items instead of only describing the issue.
- Review the revised spec point by point for completeness and effectiveness before delivering it.
