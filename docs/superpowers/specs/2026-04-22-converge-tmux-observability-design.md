# Converge Tmux Observability Design

**Goal**

Add optional `tmux`-backed observability to the converge runners without changing the existing sequential handoff loop or per-step artifact contract.

**Scope**

- Add `--tmux` to `scripts/converge.py`, `scripts/converge.sh`, and `scripts/converge.rb`.
- Add `--tmux-session-name <name>` as an optional override.
- Keep non-`tmux` behavior unchanged.
- Keep `stdout.log`, `stderr.log`, `handoff.md`, `effective_prompt.md`, and `exit_code.txt` as the canonical artifacts.

**CLI**

- `--tmux` enables optional tmux-backed observability.
- `--tmux-session-name` sets the detached session name. If omitted, the runner generates a unique name.
- In `--tmux` mode, the runner prints the session name and attach command before starting the loop.

**Runtime Model**

- The loop remains strictly sequential. Step `N+1` starts only after step `N` exits and `exit_code.txt` is recorded.
- In `--tmux` mode, each converge invocation creates one detached tmux session.
- Each step runs in its own tmux window named with the step number and a sanitized prompt-derived suffix.
- Step output must remain visible in the tmux pane while still being persisted to `stdout.log` and `stderr.log`.
- Finished windows remain visible for inspection during the run.

**Execution Strategy**

- Non-`tmux` mode keeps the current direct execution path.
- `tmux` mode writes a small per-step shell wrapper into the step directory.
- The wrapper feeds `effective_prompt.md` to the agent command on stdin and duplicates output with `tee`:

```bash
agent_cmd < effective_prompt.md > >(tee stdout.log) 2> >(tee stderr.log >&2)
```

- The wrapper writes the child exit code to `exit_code.txt` and exits with the same status.
- The parent runner waits for `exit_code.txt` to appear before advancing to the next step.

**Failure Handling**

- If `--tmux` is requested and `tmux` is unavailable, the runner exits with a clear error.
- If the requested session name already exists, the runner exits with a clear error.
- If tmux session or window creation fails, the runner exits immediately.
- No silent fallback to non-`tmux` mode.

**Testing**

- Add red/green tests around the public CLI contract in the Python runner first.
- Use a fake `tmux` executable in tests so the contract can be verified without a real tmux server.
- Verify non-`tmux` behavior still works.
- Mirror the same behavior into shell and Ruby after the Python contract is green.

