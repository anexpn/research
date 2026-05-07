# Verification Language

This document defines the core language for design-time, automatable functional verification.

The primary artifact is a Markdown verification spec written in controlled natural language. The language is for stating what behavior must be true, what subject that behavior is about, and where that behavior is observed.

## Scope

This language is for functional verification that can be automated.

It does not, in v1:

- cover non-automatable acceptance criteria;
- make non-functional requirements first-class;
- require YAML, JSON, or another authoring schema;
- define exact compilation into any one test framework;
- make mutation testing or coverage thresholds part of the authoring language.

## Core Model

The unit of thought is a verification item, not a test case and not a schema record.

Each verification item has four parts:

- `Subject`: the externally meaningful thing whose behavior is being constrained.
- `Observation`: where that behavior is observed.
- `Pattern`: the statement shape that best matches the obligation.
- `Statement`: what behavior must be true.

`Subject` should name the narrowest externally meaningful thing that carries the obligation. Prefer domain subjects such as `publish lifecycle`, `lambertian material response`, `foreground silhouette anti-aliasing behavior`, or `CLI render invocation`.

`Observation` should name the externally visible surface or measurement surface where the subject is checked. Prefer observations such as `listing responses`, `stored document status`, `stderr error text`, `output image dimensions`, or `pixel variance in the designated edge band`.

Verification items should be organized by contract: a coherent area of externally observable behavior such as a publish lifecycle, parser contract, selection model, or render invocation contract.

When revising older specs that include `Required evidence`, remove that section from the final shape. If it contains real behavioral requirements such as rejection behavior, sequence behavior, equivalence, or bounds, move that content into one or more `Statement` items. If it only describes test technique or desired coverage strength, drop it.

## Statement Patterns

V1.1 standardizes three statement patterns.

When revising older specs, treat legacy labels as follows:

- `Example` -> `Scenario`
- `Rule` -> `Property`
- `Transition` -> `Property`
- `Invariant` -> `Property`
- `Equivalence` -> `Property`
- `Observational Equivalence` -> `Property`

### Scenario

Form:

`Given <context>, when <action>, then <observable outcome>.`

Use for concrete scenarios, regressions, and named edge cases.

### Property

Form:

`For any <input domain or context>, if <precondition or trigger>, then <observable property>.`

Use for general correctness over a domain, named partitions, workflow transitions, invariants, rejection behavior, and equivalence claims.

### Progress

Form:

`From <state or trigger>, <outcome> eventually becomes true [within <bound>].`

Use for eventual completion, delivery, convergence, and bounded asynchronous behavior.

## Deliberate Omissions

- `Boundary` is not a top-level pattern. Express boundary behavior inside `Scenario` or `Property`.
- `Property test`, `table test`, and `mutation test` are not language primitives. They describe verifier technique or verifier strength, not the behavior statement itself.
- Given-When-Then is useful, but only as the `Scenario` pattern. It is not the whole language.
- `Transition`, `Invariant`, and `Observational Equivalence` are not top-level patterns. Express them as tighter `Property` statements.

## Authoring Rules

Every verification item must satisfy all of the following rules.

### External

State observable behavior, not internals.

Prefer:

- visible state;
- returned values;
- persisted outcomes;
- emitted responses;
- externally visible errors;
- output artifacts and named observation regions.

Avoid:

- helper names;
- private data structures;
- mocks;
- call counts;
- storage details that are not part of the public contract.

### Anchored

Name the subject and observation explicitly.

Avoid hidden generic subjects such as `the system`, `the feature`, or `the render` when a narrower subject exists.

Prefer subjects such as `glass material refraction behavior` over `the renderer`, and observations such as `pixel intensity in the caustic region` over `the output`.

### Singular

State one obligation at a time. If two outcomes can fail independently, split them.

### Scoped

Name the relevant context, state, input domain, or operation family explicitly.

### Quantified

Use explicit quantification when it matters, such as `for any`, `for every`, `there exists`, `never`, `only if`, or `exactly once`.

### Complete

The statement must say enough to derive the intended verification strategy. If sequence behavior, rejection behavior, equivalence, or a bound matters, say so in the statement instead of outsourcing it to a separate note. A good `Property` statement should usually be enough to derive a property test directly.

### Falsifiable

A reader should be able to imagine a concrete counterexample.

### Implementation-Agnostic

Describe the contract without depending on code structure, unless an implementation detail is itself part of the externally visible behavior.

### Domain-Language

Prefer product or problem-domain terms over module, framework, or pattern language.

## Rejection Rules

The following are non-compliant and should be rewritten:

- vague claims such as `works correctly`, `handles edge cases`, or `stays in sync`;
- statements with missing subject, missing observation surface, missing scope, or missing observable outcome;
- statements that combine multiple independently failing obligations;
- statements framed mainly in terms of implementation details;
- `Property` statements with an implicit domain, trigger, or observable result;
- statements that leave important variation implicit when that variation changes what must be verified, such as rejection behavior, sequence behavior, equivalence, or bounds;
- statements that rely on a separate note to supply behavior that should have been stated as part of the obligation.

Weak statements such as these should be rejected:

- `Publishing works correctly.`
- `The parser handles edge cases.`
- `The UI keeps state in sync.`
- `The render looks correct.`

They should be rewritten into precise statements such as:

- `For any document in Draft, if Publish is invoked, then stored status becomes Published and listing visibility becomes true.`
- `For any document already in Published, if Publish is invoked, then the invocation is rejected and stored status remains Published.`
- `For any valid token stream, parsing consumes the entire stream or reports the first unconsumed position.`
- `For any selected-item removal from a non-empty visible selection, the visible selection moves to the next visible item, or becomes empty if none remain.`
- `Given the canonical spheres scene, when rendered at 1 sample per pixel and at N samples per pixel, the higher-sample render has lower variance in the designated silhouette edge band.`

As a quick check, every item should answer:

- what subject is being constrained?
- where is that subject observed?
- under what conditions?
- over what action, event, state change, or input family?
- what observable result must hold?
- what important variation must also be true, if any, such as rejection, sequence behavior, equivalence, or bounds?
- what would count as failure?

## Authoring Form

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
