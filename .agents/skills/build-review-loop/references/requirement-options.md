# Requirement Options

Use these option sets when Human wants role-specific requirements. Present the listed options as structured choices when a structured-choice UI is available. Add `none` to both lists. Add `other` only when Human asks for something outside these sets.

## Builder options

- Follow TDD for each delta.
- Keep diffs local and avoid unrelated cleanup.
- Run targeted verification before handoff.
- Avoid adding new dependencies.
- Update brief-adjacent docs when behavior changes.

## Reviewer options

- Block on missing requirement coverage.
- Block on missing verification evidence.
- Prioritize regressions and correctness over style.
- Require the smallest concrete next delta.
- Ignore optional polish unless Human asked for it.
