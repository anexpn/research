# Commit Agent Inference

## Goal

Allow `ideas/005-commit/commit.sh` to run without `--agent` by inferring the first supported agent CLI available on `PATH`.

## Decision

When `--agent` is omitted, infer in this order:

1. `codex`
2. `claude`
3. `cursor-agent`

If none of those binaries are available, fail with a clear error that names the searched order.

If `--agent` is provided, it overrides inference.

## Approaches Considered

1. Infer once after CLI parsing.
   This keeps selection logic separate from command construction and is the simplest path to test.
2. Fold inference into `resolve_agent_command()`.
   This would work, but it mixes preset resolution with PATH probing and makes the control flow harder to read.
3. Add `--agent auto`.
   This keeps the interface explicit, but it does not remove the friction that motivated the change.

Selected approach: infer once after CLI parsing.

## Implementation Shape

- Add a small helper that checks `command -v` for each supported agent in priority order.
- Use the inferred preset only when `--agent` is missing.
- Leave preset-specific command construction unchanged.
- Extend the `bats` suite to cover:
  - inferring `codex`
  - falling back to `claude`
  - failing when none of the supported CLIs are on `PATH`

## Notes

- No success logging is added.
- Existing `--agent` and `--agent-arg` behavior remains unchanged.
