---
name: summon
description: Start a new Codex agent in tmux and print metadata for finding the launched pane or isolated session.
---

# Summon

Use this skill when a new Codex agent must be started. It owns startup only: creating a tmux window or pane, launching Codex, and printing key/value metadata for the caller.

Use `talk` after a reachable pane already exists. `summon` does not send XML protocol fragments, wait for replies, assign tasks, track lifecycle, clean up agents, or keep a registry.

## Helper

Run the helper relative to this skill directory:

```bash
<this-skill-directory>/scripts/summon codex [--name <name>] [--cd <dir>] [--mode shared|isolated] [--layout window|pane] [--socket <socket-name>] [--session <session-name>] [--dry-run] [-- <initial-prompt>]
```

V1 supports only the `codex` agent kind. Unsupported kinds fail clearly.

## Modes

Prefer shared mode when follow-up communication through `talk` is needed. Shared mode starts Codex in the caller's current tmux server and prints `talk_target: <pane-id>`.

Use isolated mode when separation is more important than direct messaging. Isolated mode launches in a named tmux socket/session and omits `talk_target` because the current `talk` helper does not communicate across tmux sockets.

Isolated mode requires an initial prompt. Without it, the caller would create an idle agent that ordinary `talk` cannot reach from the original socket.

## Output

The helper prints plain key/value lines:

```text
agent_kind: codex
name: codex-review
mode: shared
socket:
session: research
window: codex-review
pane: %42
cwd: /Users/jun/code/mine/research
talk_target: %42
```

With `--dry-run`, it also prints `dry_run: true` and the intended Codex command.

## Reference

See `references/usage.md` for examples.
