# converge

`scripts/converge.sh` is a shell-based converging loop runner with optional session artifacts, handoff files, `tmux` observability, and resumable runs.

## Usage

### Agent command presets (non-interactive, no approval prompts)

- `codex`: `codex exec --dangerously-bypass-approvals-and-sandbox -`
- `claude`: `claude -p --permission-mode bypassPermissions`
- `cursor-agent`: `cursor-agent -p --yolo --trust --approve-mcps`

These are intended for automated loop runs. `bypassPermissions` and `--yolo` are high-trust settings; use only in trusted workspaces.

### Basic run

```bash
./scripts/converge.sh \
  --prompt-file ./tmp/prompts/builder.md \
  --prompt-file ./tmp/prompts/reviewer.md \
  --agent-preset codex \
  --max-steps 2
```

### Rotate agents independently from prompts

```bash
./scripts/converge.sh \
  run \
  --session-dir ./tmp/session-a \
  --prompt-file ./tmp/prompts/builder.md \
  --prompt-file ./tmp/prompts/reviewer.md \
  --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" \
  --agent-cmd "claude -p --permission-mode bypassPermissions" \
  --max-steps 4
```

### Keep session artifacts but disable handoff

```bash
./scripts/converge.sh \
  run \
  --session-dir ./tmp/session-a \
  --prompt-file ./tmp/prompts/builder.md \
  --prompt-file ./tmp/prompts/reviewer.md \
  --agent-cmd "claude -p --permission-mode bypassPermissions" \
  --no-handoff \
  --tmux
```

### Preview plan without executing

```bash
./scripts/converge.sh run \
  --session-dir ./tmp/session-a \
  --prompt-file ./tmp/prompts/builder.md \
  --prompt-file ./tmp/prompts/reviewer.md \
  --agent-preset codex \
  --agent-preset claude \
  --max-steps 6 \
  --dry-run
```

### Resume an existing session

```bash
./scripts/converge.sh resume \
  --session-dir ./tmp/session-a \
  --max-steps 10
```

## Prompt rotation

- Prompts rotate by step based on repeated `--prompt` and/or `--prompt-file` flags.
- Repeated `--agent-cmd` flags rotate independently of prompt selection.
- Repeated `--agent-preset` flags also rotate independently (same as `--agent-cmd`).

## Runtime protocol

For each step, the runner builds an effective prompt with protocol metadata plus the selected role prompt.

Always included:

- `step`
- `agent_cmd`

Included when handoff is enabled:

- `input_handoff`
- `output_handoff`

Handoff mode:

- default: enabled when `--session-dir` is present
- disabled when no `--session-dir` is provided
- `--no-handoff` disables handoff even with a session dir

## Artifacts

Without `--session-dir`:

- No session tree is created.

With `--session-dir`:

- `<session-dir>/run/sNNN/effective_prompt.md`
- `<session-dir>/run/sNNN/stdout.log`
- `<session-dir>/run/sNNN/stderr.log`
- `<session-dir>/run/sNNN/exit_code.txt`
- `<session-dir>/run/loop/loop.log`

With handoff enabled:

- `<session-dir>/run/sNNN/handoff.md`

`loop.log` records one line per step including timestamp, step, prompt path, quoted `agent_cmd`, exit code, and elapsed seconds.

## Optional tmux mode

- `--tmux` runs each step in its own `tmux` window in a detached session.
- tmux sessions are preserved by default after completion/interruption so you can inspect logs.
- `--tmux-cleanup` opt-in kills the tmux session automatically at exit/interruption.
- `--tmux-session-name <name>` overrides the generated session name.
- The loop still executes sequentially; `tmux` provides observability.
- `--tmux` works with or without `--session-dir`.
- With `--session-dir`, output is mirrored into `stdout.log` and `stderr.log` and exit status is written to `exit_code.txt`.
- When enabled, the runner prints `tmux_session=` and shell-escaped `tmux_attach_cmd=`.

## Commands and flags

- `run` (default when omitted):
  - Prompt inputs: `--prompt`, `--prompt-file` (both repeatable)
  - Agent inputs: `--agent-cmd`, `--agent-preset` (all repeatable)
  - Optional: `--session-dir`, `--no-handoff`, `--max-steps` (default `10`), `--tmux`, `--tmux-cleanup`, `--tmux-session-name`, `--dry-run`
- `resume`:
  - Required: `--session-dir`
  - Optional: `--max-steps` (only supported reassignment on resume), `--dry-run`

