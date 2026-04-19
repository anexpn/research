# Verification Strength Standard

## Purpose

Define the minimum quality bar for verification artifacts so converge rounds do not accept assertion-light checks.

## Scope

Applies to:

- `verification_spec.md` quality review in converge initialization.
- Builder-authored automated verification artifacts.
- Inspector review of automated verification artifacts.
- Judge resolution when accepting or requesting deltas for verification quality.

## Verification Spec Requirements

For each automated scenario, the spec must define measurable or falsifiable outcomes. At least one of:

- exact expected value,
- numeric threshold or bound,
- tolerance/epsilon window,
- required ordering/comparator relation,
- deterministic artifact property.

Not acceptable as a sole expectation:

- purely qualitative language,
- "works", "looks correct", or "changes consistently" without measurable criteria,
- pass conditions that depend only on symbol presence.

## Automated Assertion Requirements

Each automated scenario must contain at least one criterion-linked behavioral assertion that fails on regression.

Allowed assertion shapes include:

- value equality/inequality against expected behavior,
- bounded numeric checks (for example runtime or metric thresholds),
- tolerance checks for floating-point or geometry behavior,
- explicit ordering comparisons (for example improved metric vs baseline),
- deterministic structural checks on generated artifacts.

Weak assertion anti-patterns (insufficient alone):

- `assert object is not None`,
- `assert hasattr(module, "...")`,
- import-only or construction-only checks with no behavior validation.

These may appear only as setup checks and must be followed by behavioral assertions.

## Inspector Enforcement

Inspector must fail assertion-strength audit when any automated scenario lacks meaningful behavioral assertions, and provide:

- scenario path/id,
- why assertion is weak,
- concrete stronger assertion proposal tied to criterion intent.

Suggested severity:

- `medium` when weakness risks false green outcomes,
- `high` when weakness invalidates criterion closure.

## Judge Enforcement

Judge must not mark automated criterion closure as satisfied when Inspector reports assertion-strength failure, unless explicit evidence-backed override is documented.

