---
name: write-verification-spec
description: Use when Human asks Codex to turn a design doc, behavior description, workflow, API contract, bug report, or existing verification draft into a Markdown verification spec with compliant Pattern, Statement, and Required evidence sections.
---

# Write Verification Spec

This skill is self-contained. Treat the embedded verification language reference below as authoritative for statement patterns, authoring rules, rejection rules, evidence vocabulary, and item shape.

## Verification Language Reference

### Scope

This language is for design-time, automatable functional verification.

It does not, in v1:

- cover non-automatable acceptance criteria;
- make non-functional requirements first-class;
- require YAML, JSON, or another authoring schema;
- define exact compilation into any one test framework;
- make mutation testing or coverage thresholds part of the authoring language.

### Core Model

The unit of thought is a verification statement, not a test case and not a schema record.

The primary artifact is a Markdown verification spec written in controlled natural language. The language states what behavior must be true and what automated evidence is required before that behavior can be treated as verified.

Each verification item has two parts:

- `Statement`: what behavior must be true.
- `Required evidence`: what automated checking is required before the statement can be considered satisfied.

Organize verification items by contract: a coherent area of externally observable behavior such as a publish lifecycle, parser contract, or selection model.

### Statement Patterns

- `Example`
  Form: `Given <context>, when <action>, then <observable outcome>.`
  Use for concrete scenarios, regressions, and named edge cases.
- `Rule`
  Form: `For any <input domain>, if <precondition>, then <observable property>.`
  Use for general correctness over a domain, named partitions, and property-style obligations.
- `Transition`
  Form: `From <state>, on <event>, the system moves to <state'> and <observable effects>.`
  Use for workflows, protocols, and lifecycle behavior.
- `Invariant`
  Form: `After any <operation family>, <condition> always holds.`
  Use for safety properties over sequences, not only single operations.
- `Equivalence`
  Form: `<process A> and <process B> are equivalent with respect to <observation>.`
  Use for round-trips, compatibility, normalization, idempotence, and semantic preservation.

### Deliberate Omissions

- `Boundary` is not a top-level pattern. Express boundary behavior inside `Example` or `Rule`.
- `Property test`, `table test`, and `mutation test` are verifier techniques, not behavior statement primitives.
- Given-When-Then is useful only as the `Example` pattern. It is not the whole language.

### Authoring Rules

Every verification statement must satisfy all of these rules:

- `External`: state observable behavior, not internals. Prefer visible state, returned values, persisted outcomes, emitted responses, and externally visible errors. Avoid helper names, private data structures, mocks, call counts, and storage details that are not part of the public contract.
- `Singular`: state one obligation at a time. If two outcomes can fail independently, split them.
- `Scoped`: name the relevant context, state, input domain, or operation family explicitly.
- `Quantified`: use explicit quantification when it matters, such as `for any`, `for every`, `there exists`, `never`, `only if`, or `exactly once`.
- `Falsifiable`: a reader should be able to imagine a concrete counterexample.
- `Implementation-agnostic`: describe the contract without depending on code structure, unless an implementation detail is itself part of the externally visible behavior.
- `Domain-language`: prefer product or problem-domain terms over module, framework, or pattern language.

Quick check for every statement:

- under what conditions?
- over what action or input family?
- what observable result must hold?
- what would count as failure?

### Rejection Rules

Reject and rewrite:

- vague claims such as `works correctly`, `handles edge cases`, or `stays in sync`;
- statements with missing scope or missing observable outcome;
- statements that combine multiple independently failing obligations;
- statements framed mainly in terms of implementation details;
- evidence requirements such as `add good tests` or `cover this well`;
- broad claims supported only by one concrete example when the real obligation is a `Rule`, `Invariant`, or `Equivalence`.

Weak statements such as these are non-compliant:

- `Publishing works correctly.`
- `The parser handles edge cases.`
- `The UI keeps state in sync.`

Rewrite them into precise statements such as:

- `From Draft, on Publish, the document becomes Published and appears in listing responses.`
- `For any valid token stream, parsing consumes the entire stream or reports the first unconsumed position.`
- `After removing a selected item, the visible selection moves to the next visible item, or becomes empty if none remain.`

### Evidence Language

Use a controlled evidence vocabulary that names coverage shape rather than a test framework:

- `Concrete example`: require one or more explicit examples.
- `Input family coverage`: require generated or enumerated checks over a named domain or partition.
- `State transition coverage`: require all named transitions, or all outgoing transitions from a named state.
- `Sequence coverage`: require checks over operation sequences, not only single operations.
- `Equivalence coverage`: require two processes to match on a named observation across a domain.
- `Rejection coverage`: require invalid inputs or forbidden operations to fail in the specified observable way.
- `Counterexample search`: require generated search for violating cases over a named domain.

### Evidence Rules

- Evidence should strengthen belief in the statement, not restate it in weaker form.
- Evidence should name a coverage shape, not a test framework.
- Evidence should focus on automatable proof.
- Evidence strength should match claim strength.
- One happy-path example is normally insufficient for `Rule`, `Invariant`, and `Equivalence` unless the claim is explicitly narrow.

### Authoring Form

Each contract should contain one or more verification items with this shape:

```md
## Contract: <contract name>

### <short item name>

Pattern
<Example | Rule | Transition | Invariant | Equivalence>

Statement
<controlled natural-language verification statement>

Required evidence
- <controlled evidence requirement>
- <controlled evidence requirement>
```

Stable identifiers may be added when helpful, but they are optional. Headings should remain readable as normal language.

### Example Spec

```md
# Document Publish Verification Spec

## Scope
This spec covers the functional correctness of publishing a document.

## Contract: Publish lifecycle

### Publish changes status and visibility
Pattern
Transition

Statement
From Draft, on Publish, the document moves to Published and becomes visible in listing responses.

Required evidence
- State transition coverage for every outgoing event from Draft.
- Rejection coverage for Publish from any non-publishable state.
- Concrete example showing that a published document appears in listing responses.

### Publish preserves body content
Pattern
Invariant

Statement
After publishing, the document body content remains unchanged.

Required evidence
- Concrete example covering a representative publish flow.
- Counterexample search over valid draft documents with varying body content.

### Publish succeeds exactly once
Pattern
Rule

Statement
For any draft that satisfies all publish preconditions, Publish succeeds exactly once.

Required evidence
- Input family coverage over drafts that vary each publish precondition independently.
- Rejection coverage for a repeated Publish on the same document.

### API and UI publish are equivalent
Pattern
Equivalence

Statement
Publishing a document through the API and publishing the same document through the UI are equivalent with respect to stored status and listing visibility.

Required evidence
- Equivalence coverage over representative publishable drafts.
- Rejection coverage for a document that fails publish preconditions through both entry points.
```

## Workflow

1. Extract externally observable behavior.
   Ignore implementation details unless they are themselves externally visible.
   Ignore non-functional requirements and non-automatable acceptance criteria in v1.
   If the source mixes multiple features, split them into separate contracts.
2. Define contracts before items.
   Group behavior by coherent external contracts such as a publish lifecycle, parser contract, selection model, or sync protocol.
   Name each contract in domain language.
3. Choose the narrowest statement pattern.
   Use `Example` for a concrete scenario, regression, or named edge case.
   Use `Rule` for a quantified input domain or partition.
   Use `Transition` for state, event, next-state, and observable-effect behavior.
   Use `Invariant` for a condition that must hold after an operation family or over sequences.
   Use `Equivalence` for round-trips, normalization, idempotence, or matching entry points.
4. Write one obligation per item.
   Make context, action or input family, and observable outcome explicit.
   Use quantifiers when the claim is broad, such as `for any`, `never`, `only if`, or `exactly once`.
   If two outcomes can fail independently, split them into separate items.
   Prefer domain terms over module, framework, or test-tool terms.
   Ask what concrete counterexample would falsify the statement and rewrite until the failure is obvious.
5. Choose required evidence that matches the claim.
   Use only the controlled evidence vocabulary from the embedded reference above.
   Name coverage shape, not frameworks or test libraries.
   Strengthen broad claims with input-family, transition, sequence, equivalence, rejection, or counterexample coverage as appropriate.
   Do not support a broad `Rule`, `Invariant`, or `Equivalence` claim with only one happy-path example unless the claim is intentionally narrow.
6. Assemble the spec in Markdown.
   Use readable headings.
   Add `## Scope` when the boundary needs to be explicit.
   Follow the item shape from the embedded reference above exactly.
7. Review the written spec point by point before delivering it.
   Re-read every contract and every verification item in order.
   Check `Completeness`: the source's externally observable obligations are covered or explicitly called out as assumptions or open questions; each item has `Pattern`, `Statement`, and `Required evidence`; implied rejection or edge-case obligations are not silently omitted.
   Check `Effectiveness`: the chosen pattern matches the claim; the statement satisfies the authoring rules; the required evidence is strong enough for the claim and is not limited to a happy path when the statement is broad.
   If a point fails either check, rewrite the spec inline before delivering it and mention any remaining ambiguity explicitly.

## Writing Checks

- Reject vague claims such as `works correctly`, `handles edge cases`, or `stays in sync`.
- Reject statements with missing scope, missing observable outcome, or mainly internal wording.
- Reject compound obligations that should be split.
- Narrow the claim or strengthen the evidence when the statement is broader than the required evidence.
- If the source artifact leaves behavior ambiguous, surface the gap as an open question or explicit assumption instead of inventing details.
- After the draft is written, review every contract and item point by point for `Completeness` and `Effectiveness`.
- `Completeness` asks whether the spec covers the source's externally observable obligations with compliant item shape and whether any meaningful omission is called out explicitly.
- `Effectiveness` asks whether each item's pattern, statement, and evidence actually support verification of the claimed behavior with enough strength to catch realistic failures.

## Output Shape

Use this skeleton unless Human asked for a different surrounding format:

```md
## Contract: <contract name>

### <short item name>
Pattern
<Example | Rule | Transition | Invariant | Equivalence>

Statement
<controlled natural-language verification statement>

Required evidence
- <controlled evidence requirement>
- <controlled evidence requirement>
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
