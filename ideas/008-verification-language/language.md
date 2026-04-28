# Verification Language

This document defines the core language for design-time, automatable functional verification.

The primary artifact is a Markdown verification spec written in controlled natural language. The language is for stating what behavior must be true and what automated evidence is required before that behavior can be treated as verified.

## Scope

This language is for functional verification that can be automated.

It does not, in v1:

- cover non-automatable acceptance criteria;
- make non-functional requirements first-class;
- require YAML, JSON, or another authoring schema;
- define exact compilation into any one test framework;
- make mutation testing or coverage thresholds part of the authoring language.

## Core Model

The unit of thought is a verification statement, not a test case and not a schema record.

Each verification item has two parts:

- `Statement`: what behavior must be true.
- `Required evidence`: what automated checking is required before the statement can be considered satisfied.

Verification items should be organized by contract: a coherent area of externally observable behavior such as a publish lifecycle, parser contract, or selection model.

## Statement Patterns

V1 standardizes five statement patterns.

### Example

Form:

`Given <context>, when <action>, then <observable outcome>.`

Use for concrete scenarios, regressions, and named edge cases.

### Rule

Form:

`For any <input domain>, if <precondition>, then <observable property>.`

Use for general correctness over a domain, named partitions, and property-style obligations.

### Transition

Form:

`From <state>, on <event>, the system moves to <state'> and <observable effects>.`

Use for workflows, protocols, and lifecycle behavior.

### Invariant

Form:

`After any <operation family>, <condition> always holds.`

Use for safety properties over sequences, not only single operations.

### Equivalence

Form:

`<process A> and <process B> are equivalent with respect to <observation>.`

Use for round-trips, compatibility, normalization, idempotence, and semantic preservation.

## Deliberate Omissions

- `Boundary` is not a top-level pattern. Express boundary behavior inside `Example` or `Rule`.
- `Property test`, `table test`, and `mutation test` are not language primitives. They describe verifier technique or verifier strength, not the behavior statement itself.
- Given-When-Then is useful, but only as the `Example` pattern. It is not the whole language.

## Authoring Rules

Every verification statement must satisfy all of the following rules.

### External

State observable behavior, not internals.

Prefer:

- visible state;
- returned values;
- persisted outcomes;
- emitted responses;
- externally visible errors.

Avoid:

- helper names;
- private data structures;
- mocks;
- call counts;
- storage details that are not part of the public contract.

### Singular

State one obligation at a time. If two outcomes can fail independently, split them.

### Scoped

Name the relevant context, state, input domain, or operation family explicitly.

### Quantified

Use explicit quantification when it matters, such as `for any`, `for every`, `there exists`, `never`, `only if`, or `exactly once`.

### Falsifiable

A reader should be able to imagine a concrete counterexample.

### Implementation-Agnostic

Describe the contract without depending on code structure, unless an implementation detail is itself part of the externally visible behavior.

### Domain-Language

Prefer product or problem-domain terms over module, framework, or pattern language.

## Rejection Rules

The following are non-compliant and should be rewritten:

- vague claims such as `works correctly`, `handles edge cases`, or `stays in sync`;
- statements with missing scope or missing observable outcome;
- statements that combine multiple independently failing obligations;
- statements framed mainly in terms of implementation details;
- evidence requirements such as `add good tests` or `cover this well`;
- broad claims supported only by one concrete example when the claim is really a `Rule`, `Invariant`, or `Equivalence` obligation.

Weak statements such as these should be rejected:

- `Publishing works correctly.`
- `The parser handles edge cases.`
- `The UI keeps state in sync.`

They should be rewritten into precise statements such as:

- `From Draft, on Publish, the document becomes Published and appears in listing responses.`
- `For any valid token stream, parsing consumes the entire stream or reports the first unconsumed position.`
- `After removing a selected item, the visible selection moves to the next visible item, or becomes empty if none remain.`

As a quick check, every statement should answer:

- under what conditions?
- over what action or input family?
- what observable result must hold?
- what would count as failure?

## Evidence Language

`Required evidence` uses a controlled vocabulary that names the coverage shape rather than a test framework.

### Concrete example

Require one or more explicit examples.

### Input family coverage

Require generated or enumerated checks over a named domain or partition.

### State transition coverage

Require all named transitions, or all outgoing transitions from a named state.

### Sequence coverage

Require checks over operation sequences, not only single operations.

### Equivalence coverage

Require two processes to match on a named observation across a domain.

### Rejection coverage

Require invalid inputs or forbidden operations to fail in the specified observable way.

### Counterexample search

Require generated search for violating cases over a named domain.

## Evidence Rules

- Evidence should strengthen belief in the statement, not restate it in weaker form.
- Evidence should name a coverage shape, not a test framework.
- Evidence should focus on automatable proof.
- Evidence strength should match claim strength.
- One happy-path example is normally insufficient for `Rule`, `Invariant`, and `Equivalence` statements unless the claim is explicitly narrow.

## Authoring Form

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

## Example Spec

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
