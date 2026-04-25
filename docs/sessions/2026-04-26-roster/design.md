# Roster Skill Design

## Context

The current agent collaboration primitives are intentionally narrow:

- `talk` sends structured XML request/reply messages to an already-known tmux pane.
- `summon` starts Codex agents in tmux and sends fixed same-socket lifecycle slash commands such as `/new` and `/exit`.

The remaining gap is address discovery. A caller often needs to answer "which panes look like agents?" before choosing a `talk` target or a `summon` lifecycle target. This should not become a registry, task tracker, scheduler, health checker, or conversation log.

## Goal

Create a stateless `roster` skill that lists and resolves tmux panes that appear to be agent panes.

`roster` reads only live tmux data from the current tmux server. It stores no aliases, roles, durable state, task ownership, health status, or message history.

## Non-Goals

- No persistent registry or state file.
- No aliases or role metadata.
- No task assignment or task status tracking.
- No lifecycle operations.
- No message sending.
- No health, idle, ready, or reachability assertions.
- No cross-socket discovery in v1.
- No background daemon or polling loop.

## CLI

The helper lives at:

```bash
.agents/skills/roster/scripts/roster
```

Command shape:

```bash
roster list [--all]
roster get [--all] <query>
```

`list` prints all detected agent panes in the current tmux server.

`list --all` prints all panes, including panes that do not match agent detection.

`get <query>` resolves a query to exactly one detected agent pane and prints that pane. If the query matches no detected agent panes or matches more than one, it exits nonzero with a clear error.

`get --all <query>` resolves against all panes instead of only detected agent panes.

## Detection

V1 detection is conservative and uses only tmux-visible fields.

A pane is included by default when either condition is true:

1. `pane_current_command` is a known agent command.
2. The tmux window name matches a summon-style agent prefix.

Initial known agent commands:

- `codex`

Initial summon-style window prefixes:

- `codex-`

Detection does not prove that the pane is healthy, idle, safe to message, or currently able to respond. It only explains why the pane was classified as an agent candidate.

`--all` disables filtering. Non-detected panes should use:

```text
agent_kind: unknown
detection: none
```

## Query Matching

`get <query>` matches against tmux-visible address fields:

- pane id, such as `%42`
- session name
- window name
- window id, such as `@7`
- window index
- pane index
- tmux target forms derived from session, window index or name, and pane index, such as `research:2.1`
- current working directory
- current command

If exactly one pane matches, `roster` prints that pane's record.

If multiple panes match, `roster` prints a concise ambiguity error and enough candidate fields for the caller to choose a more precise query, preferably a pane id.

If no pane matches, `roster` fails clearly.

## Output

Output uses plain key/value blocks, matching the style of `summon`.

Example detected pane:

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

Example pane detected by window name:

```text
agent_kind: codex
pane: %43
session: research
window: codex-review-2
window_id: @8
window_index: 3
pane_index: 0
cwd: /Users/jun/code/mine/research
command: zsh
detection: window-name
```

Example non-detected pane when `--all` is used:

```text
agent_kind: unknown
pane: %44
session: research
window: editor
window_id: @9
window_index: 4
pane_index: 0
cwd: /Users/jun/code/mine/research
command: nvim
detection: none
```

For multiple records, separate blocks with one blank line.

`roster` must not print fields such as `reachable_by_talk`, `healthy`, `idle`, or `ready`, because those would be behavioral claims beyond tmux discovery.

## Data Flow

1. Caller runs `summon codex --name codex-review`.
2. `summon` creates a tmux window or pane named for the agent and prints launch metadata.
3. Later, caller runs `roster get codex-review`.
4. `roster` inspects the current tmux server and resolves the query to one pane.
5. Caller may pass the returned `pane` value to `talk` or `summon`, but `roster` does not perform that action.

## Error Handling

The helper exits nonzero with a clear `roster:` error when:

- `tmux` is missing on `PATH`.
- the command is unknown.
- required arguments are missing.
- `get` finds no matching panes.
- `get` finds multiple matching panes.
- tmux pane listing fails.
- roster is run outside tmux and cannot inspect a current tmux server.

Ambiguous matches should include candidate rows with pane id, session, window index, pane index, window name, cwd, command, and detection reason.

## Skill Documentation

`.agents/skills/roster/SKILL.md` should explain:

- use `roster` when an agent pane must be discovered or resolved from live tmux state;
- use `summon` for launch and lifecycle slash commands;
- use `talk` for structured request/reply messaging after a pane is chosen;
- `roster` stores no state and makes no health or reachability claims;
- `--all` is for inspecting every pane, not for changing the default agent-filtered behavior.

## Testing

Use Bats tests with a fake `tmux` executable on `PATH`.

Coverage:

- `roster list` prints panes whose command is `codex`.
- `roster list` prints panes whose window name starts with `codex-`.
- `roster list` excludes ordinary panes by default.
- `roster list --all` includes ordinary panes with `agent_kind: unknown` and `detection: none`.
- `roster get <pane-id>` resolves exactly one detected agent pane.
- `roster get <window-name>` resolves exactly one detected agent pane.
- `roster get <query>` fails clearly when no detected agent pane matches.
- `roster get <query>` fails clearly when multiple detected agent panes match.
- `roster get --all <query>` can resolve a non-agent pane.
- tmux failures are reported with a clear `roster:` error.

## Future Work

Future designs can add support for more known agent commands such as `claude` or `cursor-agent`, explicit socket targeting, or a separate stateful primitive if durable naming becomes necessary. Those are intentionally outside v1 so `roster` remains a tmux snapshot and resolution helper.
