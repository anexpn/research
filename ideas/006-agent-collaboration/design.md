# Summon Skill Design

## Context

The existing `talk` skill gives already-running agents a structured tmux XML protocol for request/reply, dialogue turns, and no-reply coordination. It intentionally does not create tmux windows, launch Codex, isolate agents, assign work, or track agent lifecycle.

The next missing primitive is reliable agent creation. The first concrete outcome is a narrow `summon` skill that starts a new Codex agent in tmux and reports where it is. Higher-level orchestration, scheduling, registries, cleanup, and task assignment remain future work.

## Goal

Create a separate `.agents/skills/summon/` skill with one job: launch a Codex agent in tmux, optionally with an initial prompt, and print metadata that lets the caller find it.

`summon` owns startup. `talk` owns ongoing communication when the launched pane is reachable from the caller's tmux socket.

## Non-Goals

- No orchestrator.
- No scheduler.
- No task assignment policy.
- No cross-socket `talk`.
- No registry or database of running agents.
- No cleanup or reaping command.
- No automatic first message through the `talk` protocol.

## CLI

The helper lives at:

```bash
.agents/skills/summon/scripts/summon
```

Command shape:

```bash
summon codex [--name <name>] [--cd <dir>] [--mode shared|isolated] [--layout window|pane] \
             [--socket <socket-name>] [--session <session-name>] [--dry-run] \
             [-- <initial-prompt>]
```

Defaults:

- `--mode shared`
- `--layout window`
- `--cd "$PWD"`
- `--name codex-<timestamp>`
- isolated session defaults to the agent name
- isolated socket defaults to `summon-<agent-name>`

The agent kind is an explicit positional argument. V1 supports `codex`; unsupported kinds fail with a clear error. This keeps invocation explicit while leaving room for future agent profiles.

## Output

Output uses plain key/value lines so humans and scripts can consume it:

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

In shared mode, `talk_target` is the new pane id and can be passed to the `talk` helper.

In isolated mode, `talk_target` is omitted because the current `talk` helper does not communicate across tmux sockets. The helper still prints socket, session, window, pane, cwd, and name metadata for inspection or future tooling.

## Launch Modes

### Shared Mode

Shared mode launches into the caller's current tmux server and session. It is the default because it creates panes that `talk` can address.

Supported layouts:

- `window`: create a new tmux window named after the agent.
- `pane`: split the current tmux window and start Codex in the new pane.

The helper fails if shared mode is requested outside tmux and no explicit session strategy exists. V1 does not invent a session for shared mode because the expected behavior would be ambiguous.

### Isolated Mode

Isolated mode launches into a named tmux socket and session:

```bash
tmux -L <socket-name> ...
```

It creates or reuses the target isolated session, then creates a new window for the agent. V1 rejects `--layout pane` with isolated mode because panes inside a different socket are not directly useful to the caller.

Isolated mode requires an initial prompt. Without it, the caller would create an idle agent that ordinary `talk` cannot reach from the original socket.

## Initial Prompt

The optional prompt is passed directly to Codex at process start:

```bash
codex --cd <dir> <initial-prompt>
```

Without a prompt, shared mode starts:

```bash
codex --cd <dir>
```

The prompt is startup context, not a `talk` message. `summon` does not send XML fragments, does not wait for replies, and does not continue the conversation after launch.

## Data Flow

1. Caller runs `summon codex ...`.
2. The helper validates arguments and resolves the working directory, agent name, mode, layout, socket, session, and optional initial prompt.
3. The helper checks that `tmux` and `codex` exist on `PATH`.
4. The helper constructs a Codex command for the requested working directory and prompt.
5. In shared mode, it creates a window or pane in the current tmux session and starts Codex there.
6. In isolated mode, it creates or reuses the named socket/session and starts Codex in a new window there.
7. The helper queries tmux for the created pane id where possible.
8. The helper prints key/value metadata.

## Error Handling

The helper exits nonzero with a clear message when:

- `tmux` is not on `PATH`.
- `codex` is not on `PATH`.
- the working directory does not exist.
- the agent kind is unsupported.
- shared mode is requested outside tmux.
- isolated mode is requested without an initial prompt.
- isolated mode is combined with `--layout pane`.
- the requested agent name collides with an existing tmux window in the target session.
- required tmux operations fail.

V1 does not include `--reuse`; a name collision is an error.

## Skill Documentation

`.agents/skills/summon/SKILL.md` should explain:

- use `summon` when a new agent must be started;
- use `talk` only after a reachable pane already exists;
- prefer shared mode when follow-up communication through `talk` is needed;
- use isolated mode when separation is more important than later direct messaging;
- isolated mode requires an initial prompt because cross-socket `talk` is not available.

`references/usage.md` should include examples for shared window, shared pane, isolated socket/session, and dry-run.

## Testing

Use Bats tests with fake `tmux` and fake `codex` executables on `PATH`. Tests should verify command construction and tmux invocation without launching real Codex sessions.

Coverage:

- `summon codex --dry-run -- "hello"` prints the intended Codex command and metadata shape.
- shared window mode calls tmux in the current session and prints a `talk_target`.
- shared pane mode calls tmux split-window and prints a `talk_target`.
- isolated mode calls tmux with `-L <socket>` and creates or uses the requested session.
- isolated mode requires an initial prompt.
- invalid working directory fails.
- unsupported agent kind fails.
- name collision fails.
- generated names are accepted when `--name` is omitted.

## Future Work

The broader collaboration system still needs:

- an agent registry for discoverability across sockets and sessions;
- lifecycle cleanup and health checks;
- cross-socket message delivery or relay support;
- orchestrator roles for decomposition and assignment;
- scheduler policies for choosing idle agents;
- task state tracking and durable handoff records;
- role/profile definitions beyond Codex.

These are intentionally out of scope for the first `summon` skill.
