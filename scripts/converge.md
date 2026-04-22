# converge

Standalone converging loop runner with three implementations:

- `scripts/converge.sh`
- `scripts/converge.py`
- `scripts/converge.rb`

All three versions keep the same behavior and flags, including optional `tmux` observability.

## Usage

### Agent command presets (non-interactive, no approval prompts)

- `codex`: `codex exec --dangerously-bypass-approvals-and-sandbox -`
- `claude`: `claude -p --permission-mode bypassPermissions`
- `cursor-agent`: `cursor-agent -p --yolo --trust --approve-mcps`

These are intended for automated loop runs. `bypassPermissions` / `--yolo` are high-trust settings; use only in a trusted sandbox/workspace.

### Bash

```bash
./scripts/converge.sh \
  --prompt-list ./tmp/prompts.txt \
  --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" \
  --max-steps 2
```

### Python

```bash
python3 ./scripts/converge.py \
  --prompt-list ./tmp/prompts.txt \
  --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" \
  --max-steps 2
```

### Ruby

```bash
ruby ./scripts/converge.rb \
  --prompt-list ./tmp/prompts.txt \
  --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" \
  --max-steps 2
```

Repeated `--agent-cmd` flags rotate independently from `--prompt-list`:

```bash
ruby ./scripts/converge.rb \
  --session-dir ./tmp/session-a \
  --prompt-list ./tmp/prompts.txt \
  --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" \
  --agent-cmd "claude -p --permission-mode bypassPermissions" \
  --max-steps 4
```

Session-backed runs can keep artifacts while disabling handoff:

```bash
python3 ./scripts/converge.py \
  --session-dir ./tmp/session-a \
  --prompt-list ./tmp/prompts.txt \
  --agent-cmd "claude -p --permission-mode bypassPermissions" \
  --no-handoff \
  --tmux
```

## Prompt list format

One prompt file path per line in rotation order:

```text
./prompts/builder_prompt.md
./prompts/reviewer_prompt.md
```

Notes:

- empty lines ignored
- `#` comment lines ignored
- relative paths resolved relative to the prompt-list file directory
- prompts rotate from `--prompt-list`
- repeated `--agent-cmd` flags rotate independently of the prompt list

## Runtime protocol

For step `N`, the runner injects protocol text before the chosen role prompt:

- always: `step` and `agent_cmd`
- with handoff enabled: `input_handoff` and `output_handoff`

Handoff mode:

- default: `auto`
- `auto` enables handoff when `--session-dir` is present and disables it otherwise
- `--handoff` forces handoff on and requires `--session-dir`
- `--no-handoff` disables handoff even when a session dir is present

Per-step artifacts:

- without `--session-dir`: no session tree is created
- with `--session-dir`: `stdout.log`, `stderr.log`, `exit_code.txt`, `effective_prompt.md`, and `loop.log`
- `handoff.md` exists only when handoff is enabled
- `tmux` does not require `effective_prompt.md`, `exit_code.txt`, or `tmux_step.sh`

## Optional tmux mode

- `--tmux` runs each step in its own tmux window inside a detached converge-specific session.
- `--tmux-session-name <name>` overrides the generated session name.
- The loop still runs sequentially; tmux is only for live observability.
- `--tmux` works with or without `--session-dir`.
- When a session dir exists, pane output is also mirrored into `stdout.log` and `stderr.log`.
- The runner prints `tmux_session=` and a shell-ready `tmux_attach_cmd=` when tmux mode is enabled.

Loop log:

- `<session-dir>/run/loop/loop.log`
- each entry records `agent_cmd=...`

## Flags

- required: `--prompt-list`, `--agent-cmd` (repeatable)
- optional: `--session-dir`
- optional: `--handoff`
- optional: `--no-handoff`
- optional: `--max-steps` (default `10`)
- optional: `--tmux`
- optional: `--tmux-session-name`
