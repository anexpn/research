# Talk Target Info Helper

## Purpose

The talk skill currently asks agents to identify a tmux pane before sending a protocol fragment, but it does not provide a safe, skill-owned way to resolve a human name such as `codex-review` to a pane id such as `%93`. This led to confusing a window id for a pane id. The skill also showed an unsafe `--stdin` example with no producer and did not state the no-polling rule strongly enough.

## Design

Add a separate read-only helper at `.agents/skills/talk/scripts/tmuxp-info`. The existing `.agents/skills/talk/scripts/tmuxp` remains send-only. `tmuxp-info` prints the current pane and a pane table with enough fields to choose a target: window name, window id, pane id, active marker, and current path.

When called with a query, `tmuxp-info <name>` filters panes where the query matches the pane id, window name, window id, or current path. If exactly one pane matches, it prints a `target: <pane-id>` line suitable for `tmuxp --to`. If no panes match, it exits nonzero with a clear error. If multiple panes match, it exits nonzero and prints the matching rows so the caller can choose a pane id explicitly.

## Documentation

Update `SKILL.md` to make `tmuxp-info` the prescribed preflight step whenever the user gives a pane or window name instead of an exact pane id. Update the `--stdin` examples to show a producer, such as `printf ... | tmuxp request --stdin`, so agents do not invoke `--stdin` with an empty payload. Strengthen the no-polling rule: after sending a request, the agent must not use `tmux capture-pane`, `sleep`, loops, or repeated inspection to wait for a reply; replies must arrive as tmuxp protocol messages.

Mirror the helper distinction and no-polling rule in `references/protocol.md`.

## Testing

Add Bats coverage for `tmuxp-info` using a fake `tmux` executable in a temporary directory. Tests cover:

- Listing panes with current pane and pane table output.
- Resolving a unique name to a pane id.
- Reporting no match.
- Reporting ambiguous matches with candidate rows.

Keep existing `tmuxp.bats` coverage for message construction and dialogue continuation unchanged except where docs/help text requires adjustment.
