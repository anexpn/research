# Summon Existing-Agent Control Design

## Context

The current `summon` skill starts new Codex agents in tmux and prints metadata for finding the launched pane. The current `talk` skill sends structured XML request/reply messages to already-running agents, and its helper safely pastes messages into tmux panes with a temporary named buffer.

Codex also has interactive slash commands for agent lifecycle control. Sending `/new` to an existing Codex agent starts a fresh conversation on that agent. Sending `/exit` dismisses that agent. These controls are not XML protocol messages, but they need the same reliable tmux paste behavior as `talk`.

This design adds same-socket control actions to `summon` while keeping cross-socket and registry behavior out of scope.

## Goal

Add two helper actions:

```bash
.agents/skills/summon/scripts/summon new --to <pane> [--dry-run]
.agents/skills/summon/scripts/summon dismiss --to <pane> [--dry-run]
```

`new` sends `/new` to an existing Codex pane.

`dismiss` sends `/exit` to an existing Codex pane.

Both actions target panes in the current tmux socket. They do not create panes, assign work, send XML protocol fragments, wait for responses, maintain a registry, or manage isolated sockets.

## Non-Goals

- No cross-socket control of isolated agents.
- No agent registry or name database.
- No polling to verify whether `/new` or `/exit` completed.
- No XML protocol messages for slash commands.
- No change to existing `summon codex ...` launch behavior.
- No generalized arbitrary-command sender.

## CLI

The existing launch command remains unchanged:

```bash
summon codex [--name <name>] [--cd <dir>] [--mode shared|isolated] [--layout window|pane] [--socket <socket-name>] [--session <session-name>] [--dry-run] [-- <initial-prompt>]
```

New control commands:

```bash
summon new --to <pane> [--dry-run]
summon dismiss --to <pane> [--dry-run]
```

The `<pane>` value is any tmux target valid in the current socket, such as `%42` or `:1.2`. This version does not resolve human-friendly agent names; callers can use `talk/scripts/tmuxp-info` separately when they need name lookup.

Control commands reject launch-only options such as `--name`, `--cd`, `--mode`, `--layout`, `--socket`, `--session`, and trailing prompt text. This keeps errors explicit when the caller mixes launch and control modes.

## Output

Control commands print plain key/value metadata:

```text
action: new
target: %42
command: /new
```

For dismiss:

```text
action: dismiss
target: %42
command: /exit
```

With `--dry-run`, the helper also prints:

```text
dry_run: true
```

Dry runs do not call tmux.

## Data Flow

1. Caller runs `summon new --to <pane>` or `summon dismiss --to <pane>`.
2. The helper validates the action and requires `--to`.
3. The helper maps the action to a fixed slash command:
   - `new` maps to `/new`.
   - `dismiss` maps to `/exit`.
4. For dry runs, the helper prints metadata and exits.
5. For real sends, the helper creates a temporary named tmux buffer containing the slash command.
6. The helper pastes the buffer into the target pane with `tmux paste-buffer -d -t <pane> -b <buffer>`.
7. The helper waits briefly, submits Enter with `tmux send-keys -t <pane> C-m`, and prints metadata.

The tmux send path follows the `talk` helper's existing `set-buffer` and `paste-buffer` pattern because it avoids shell quoting issues and sends the slash command as one buffer payload.

## Error Handling

The helper exits nonzero with a clear `summon:` error when:

- the action is unknown;
- `--to` is missing for `new` or `dismiss`;
- launch-only options are used with a control action;
- trailing prompt text is provided with a control action;
- `tmux` is missing on `PATH`;
- `tmux set-buffer`, `tmux paste-buffer`, or `tmux send-keys` fails.

If `paste-buffer` fails after the buffer is created, the helper attempts to delete the temporary buffer before exiting, matching the cleanup pattern in `talk`.

## Documentation

Update `.agents/skills/summon/SKILL.md` to explain that `summon` now owns startup plus two lightweight same-socket lifecycle controls:

- use `summon codex ...` to start a new agent process;
- use `summon new --to <pane>` to send `/new` to an existing agent;
- use `summon dismiss --to <pane>` to send `/exit` to an existing agent;
- use `talk` for structured request/reply messages after a reachable pane exists.

Update `.agents/skills/summon/references/usage.md` with examples for both control actions.

## Testing

Extend `.agents/skills/summon/tests/summon.bats` and the fake `tmux` executable.

Coverage:

- `summon new --to %42 --dry-run` prints `action: new`, `target: %42`, `command: /new`, and `dry_run: true`.
- `summon dismiss --to %42 --dry-run` prints `command: /exit`.
- real `new` calls `tmux set-buffer`, `tmux paste-buffer`, and `tmux send-keys`.
- real `dismiss` sends `/exit` through the same path.
- missing `--to` fails clearly.
- launch-only options fail clearly with control actions.
- trailing prompt text fails clearly with control actions.

## Future Work

Future versions can add name resolution directly to `summon` if repeated use shows that requiring pane ids is too awkward. Cross-socket control remains a separate design because it needs explicit socket targeting and different safety checks.
