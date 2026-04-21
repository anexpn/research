# converge

Standalone converging loop runner with three implementations:

- `scripts/converge.sh`
- `scripts/converge.py`
- `scripts/converge.rb`

All three versions keep the same behavior and flags.

## Usage

### Agent command presets (non-interactive, no approval prompts)

- `codex`: `codex exec --dangerously-bypass-approvals-and-sandbox -`
- `claude`: `claude -p --permission-mode bypassPermissions`
- `cursor-agent`: `cursor-agent -p --yolo --trust --approve-mcps`

These are intended for automated loop runs. `bypassPermissions` / `--yolo` are high-trust settings; use only in a trusted sandbox/workspace.

### Bash

```bash
./scripts/converge.sh \
  --session-dir ./tmp/session-a \
  --prompt-list ./tmp/prompts.txt \
  --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" \
  --max-steps 6
```

### Python

```bash
python3 ./scripts/converge.py \
  --session-dir ./tmp/session-a \
  --prompt-list ./tmp/prompts.txt \
  --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" \
  --max-steps 6
```

### Ruby

```bash
ruby ./scripts/converge.rb \
  --session-dir ./tmp/session-a \
  --prompt-list ./tmp/prompts.txt \
  --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" \
  --max-steps 6
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

## Runtime protocol

For step `N`, the runner injects protocol text before the chosen role prompt:

- input handoff: `<session-dir>/run/s<N-1>/handoff.md` if it exists
- output handoff: `<session-dir>/run/s<N>/handoff.md`

Per-step artifacts:

- `handoff.md`
- `effective_prompt.md`
- `stdout.log`
- `stderr.log`
- `exit_code.txt`

Loop log:

- `<session-dir>/run/loop/loop.log`

## Flags

- required: `--session-dir`, `--prompt-list`, `--agent-cmd`
- optional: `--max-steps` (default `10`)

