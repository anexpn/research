---
name: roster
description: Discover and resolve live tmux panes that appear to be agent panes.
---

# Roster

Use this skill when an agent pane must be discovered or resolved from live tmux state before choosing a `talk` target or a `summon` lifecycle target.

Use `summon` to launch Codex agents and send fixed lifecycle slash commands such as `/new` or `/exit`. Use `talk` for structured request/reply messaging after a pane has been chosen.

`roster` is stateless. It stores no aliases, roles, durable state, task ownership, health status, reachability status, or message history. It only reads panes from the current tmux server and makes no claims that a pane is healthy, idle, ready, or reachable.

## Helper

Run the helper relative to this skill directory:

```bash
<this-skill-directory>/scripts/roster list [--all]
<this-skill-directory>/scripts/roster get [--all] <query>
```

By default, `list` and `get` include only panes that look like agent panes. V1 detects a Codex agent candidate when the pane's current command is `codex` or the tmux window name starts with `codex-`.

Use `--all` to inspect every pane in the current tmux server. Non-detected panes are printed with `agent_kind: unknown` and `detection: none`. `--all` is for inspection and explicit resolution across all panes; it does not change the default agent-filtered behavior.

`get <query>` resolves a query to exactly one pane. Queries can match tmux-visible address fields such as pane id, session name, window name, window id, window index, pane index, common tmux target forms, current working directory, or current command. Ambiguous or missing matches fail with a `roster:` error.

## Output

The helper prints plain key/value blocks:

```text
agent_kind: codex
pane: %42
session: research
window: codex-review
window_id: @7
window_index: 2
pane_index: 1
cwd: /Users/jun/code/mine/research
command: codex
detection: command
```
