# Converge Tmux Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional `tmux`-backed observability to all converge runners while preserving the existing sequential runtime and artifact contract.

**Architecture:** Each runner keeps its current non-`tmux` execution path. In `--tmux` mode, the runner creates one detached session per converge invocation and launches each step inside its own window through a step-local shell wrapper that mirrors live pane output into `stdout.log` and `stderr.log` with `tee`, then writes `exit_code.txt` for the parent loop to observe.

**Tech Stack:** Python stdlib, POSIX shell, Ruby stdlib, `tmux`

---

### Task 1: Lock the public tmux CLI contract with tests

**Files:**
- Create: `tests/test_converge_tmux.py`
- Test: `tests/test_converge_tmux.py`

- [ ] **Step 1: Write the failing tests**

```python
def test_python_runner_tmux_mode_keeps_live_output_and_logs():
    ...

def test_shell_runner_tmux_mode_keeps_live_output_and_logs():
    ...

def test_ruby_runner_tmux_mode_keeps_live_output_and_logs():
    ...
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m unittest tests.test_converge_tmux -v`
Expected: FAIL because the runners do not accept `--tmux` yet.

- [ ] **Step 3: Add shared test fixtures**

```python
def make_fake_tmux(bin_dir: Path) -> None:
    ...

def make_agent_script(bin_dir: Path) -> Path:
    ...
```

- [ ] **Step 4: Re-run tests to confirm the same contract still fails for missing implementation**

Run: `python3 -m unittest tests.test_converge_tmux -v`
Expected: FAIL on argument parsing or missing tmux behavior.

- [ ] **Step 5: Commit**

```bash
jj status
```

### Task 2: Implement the tmux execution path in the Python runner

**Files:**
- Modify: `scripts/converge.py`
- Test: `tests/test_converge_tmux.py`

- [ ] **Step 1: Add the failing Python-only assertion target**

```python
ap.add_argument("--tmux", action="store_true", help="Run each step in a tmux window for live observability.")
ap.add_argument("--tmux-session-name", help="Optional tmux session name override.")
```

- [ ] **Step 2: Add helper functions for tmux session names, window names, and step wrapper creation**

```python
def build_tmux_session_name(provided: str | None) -> str:
    ...

def build_window_name(step: int, prompt: Path) -> str:
    ...

def write_tmux_step_script(... ) -> Path:
    ...
```

- [ ] **Step 3: Run the tmux mode test and confirm it still fails until execution is wired**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_tmux_mode_keeps_live_output_and_logs -v`
Expected: FAIL because the runner still executes directly.

- [ ] **Step 4: Implement session creation, per-step windows, and exit-file waiting**

```python
subprocess.run(["tmux", "new-session", ...], check=True)
subprocess.run(["tmux", "set-option", "-t", session_name, "remain-on-exit", "on"], check=True)
subprocess.run(["tmux", "new-window", ...], check=True)
```

- [ ] **Step 5: Run the Python tmux test and make it pass**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_tmux_mode_keeps_live_output_and_logs -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
jj status
```

### Task 3: Mirror the contract into shell, Ruby, and docs

**Files:**
- Modify: `scripts/converge.sh`
- Modify: `scripts/converge.rb`
- Modify: `scripts/converge.md`
- Test: `tests/test_converge_tmux.py`

- [ ] **Step 1: Add shell and Ruby CLI flags**

```bash
--tmux
--tmux-session-name <name>
```

```ruby
when "--tmux" then opts[:tmux] = true
when "--tmux-session-name" then opts[:tmux_session_name] = ARGV[i + 1]
```

- [ ] **Step 2: Add runner-local helpers for session naming, window naming, and step wrapper scripts**

```bash
make_tmux_window_name() { ... }
write_tmux_step_script() { ... }
```

```ruby
def build_window_name(step, prompt) ... end
def write_tmux_step_script(...) ... end
```

- [ ] **Step 3: Run the shell and Ruby tests and confirm they fail until wired**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_shell_runner_tmux_mode_keeps_live_output_and_logs tests.test_converge_tmux.ConvergeTmuxTests.test_ruby_runner_tmux_mode_keeps_live_output_and_logs -v`
Expected: FAIL

- [ ] **Step 4: Wire tmux session creation, per-step windows, and exit waiting in both runners**

```bash
tmux new-session -d -s "$tmux_session_name" -n "$window_name" bash "$step_runner"
tmux new-window -d -t "$tmux_session_name" -n "$window_name" bash "$step_runner"
```

```ruby
system("tmux", "new-session", "-d", "-s", session_name, "-n", window_name, "bash", step_runner)
system("tmux", "new-window", "-d", "-t", session_name, "-n", window_name, "bash", step_runner)
```

- [ ] **Step 5: Make the full tmux test suite pass and update usage docs**

Run: `python3 -m unittest tests.test_converge_tmux -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
jj status
```
