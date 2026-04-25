# Summon Usage

## Shared Window

Create a new window in the current tmux session and launch Codex there:

```bash
.agents/skills/summon/scripts/summon codex --name codex-review -- "Review the current diff."
```

The output includes `talk_target`, which can be passed to the `talk` helper.

## Shared Pane

Split the current tmux window and launch Codex in the new pane:

```bash
.agents/skills/summon/scripts/summon codex --name codex-peer --layout pane -- "Inspect the failing test."
```

## Isolated Socket And Session

Launch Codex in a separate tmux socket/session:

```bash
.agents/skills/summon/scripts/summon codex \
  --mode isolated \
  --socket summon-review \
  --session review-agents \
  --name codex-isolated \
  -- "Work independently on the parser review."
```

Isolated output omits `talk_target` because the current `talk` helper cannot message across tmux sockets.

## Dry Run

Print the metadata shape and intended Codex command without creating tmux windows or panes:

```bash
.agents/skills/summon/scripts/summon codex --dry-run -- "hello"
```

## New Conversation On Existing Agent

Send `/new` to an existing Codex pane in the current tmux socket:

```bash
.agents/skills/summon/scripts/summon new --to %42
```

## Dismiss Existing Agent

Send `/exit` to an existing Codex pane in the current tmux socket:

```bash
.agents/skills/summon/scripts/summon dismiss --to %42
```
