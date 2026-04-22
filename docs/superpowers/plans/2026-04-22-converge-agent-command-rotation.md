# Converge Agent Command Rotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add independent per-step rotation of repeated `--agent-cmd` values across all converge runners without changing the existing single-command behavior or prompt rotation contract.

**Architecture:** Keep the existing prompt-list mechanism unchanged and make `--agent-cmd` repeatable in each runner. Each loop step computes its prompt and agent command independently with modulo rotation, then records the selected command in `effective_prompt.md` and `run/loop/loop.log` so both direct execution and `--tmux` execution remain auditable.

**Tech Stack:** Python stdlib, POSIX shell, Ruby stdlib, `unittest`, optional `tmux`

---

## File Structure

- `tests/test_converge_tmux.py`: black-box CLI contract tests, fake agent fixtures, and shared assertions for independent command rotation in direct and `--tmux` modes.
- `scripts/converge.py`: Python runner CLI parsing, per-step command selection, runtime header generation, execution path wiring, and loop logging.
- `scripts/converge.sh`: shell runner CLI parsing, per-step command selection, runtime header generation, execution path wiring, and loop logging.
- `scripts/converge.rb`: Ruby runner CLI parsing, per-step command selection, runtime header generation, execution path wiring, and loop logging.
- `scripts/converge.md`: user-facing usage and runtime contract documentation for repeatable `--agent-cmd`.

## Execution Notes

- This repo uses `jj`, and the current worktree already contains in-flight converge changes outside this feature.
- During execution, use `jj status` and `jj diff --git` as checkpoints after each task instead of inventing a commit-splitting workflow.
- Keep the change small: no new prompt syntax, no command-list file, no scheduler changes beyond independent modulo rotation.

### Task 1: Lock the Python contract with failing rotation tests

**Files:**
- Modify: `tests/test_converge_tmux.py`
- Test: `tests/test_converge_tmux.py`

- [ ] **Step 1: Expand the test fixtures to cover both single-prompt and rotating-prompt runs**

```python
def make_fake_agent(bin_dir: Path, name: str, stdout_text: str, stderr_text: str) -> Path:
    path = bin_dir / name
    write_executable(
        path,
        textwrap.dedent(
            f"""\
            #!/usr/bin/env bash
            set -euo pipefail
            cat >/dev/null
            printf {stdout_text!r}
            printf {stderr_text!r} >&2
            """
        ),
    )
    return path


def setUp(self) -> None:
    self.temp_dir = tempfile.TemporaryDirectory()
    self.root = Path(self.temp_dir.name)
    self.bin_dir = self.root / "bin"
    self.bin_dir.mkdir()
    make_fake_tmux(self.bin_dir)
    self.default_agent = make_fake_agent(self.bin_dir, "fake-agent", "agent stdout\n", "agent stderr\n")
    self.agent_a = make_fake_agent(self.bin_dir, "fake-agent-a", "agent a stdout\n", "agent a stderr\n")
    self.agent_b = make_fake_agent(self.bin_dir, "fake-agent-b", "agent b stdout\n", "agent b stderr\n")
    self.fake_tmux_root = self.root / "fake_tmux"
    self.fake_tmux_root.mkdir()

    self.prompt_dir = self.root / "prompts"
    self.prompt_dir.mkdir()
    (self.prompt_dir / "builder.md").write_text("Builder prompt.\n")
    (self.prompt_dir / "reviewer.md").write_text("Reviewer prompt.\n")

    self.single_prompt_list = self.root / "single-prompts.txt"
    self.single_prompt_list.write_text("./prompts/builder.md\n")
    self.rotation_prompt_list = self.root / "rotation-prompts.txt"
    self.rotation_prompt_list.write_text("./prompts/builder.md\n./prompts/reviewer.md\n")

    self.session_dir = self.root / "session"
    self.env = os.environ.copy()
    self.env["PATH"] = f"{self.bin_dir}:{self.env.get('PATH', '')}"
    self.env["FAKE_TMUX_ROOT"] = str(self.fake_tmux_root)
```

Update the existing single-command tests in the same edit so they read `self.single_prompt_list` instead of `self.prompt_list` and `self.default_agent` instead of `self.agent`.

- [ ] **Step 2: Add a reusable assertion helper plus a failing Python non-`tmux` rotation test**

```python
def assert_independent_rotation(self, result: subprocess.CompletedProcess[str]) -> None:
    self.assertEqual(result.returncode, 0, msg=result.stderr)
    expected = [
        ("s001", "builder.md", self.agent_a, "agent a stdout\n", "agent a stderr\n"),
        ("s002", "reviewer.md", self.agent_b, "agent b stdout\n", "agent b stderr\n"),
        ("s003", "builder.md", self.agent_a, "agent a stdout\n", "agent a stderr\n"),
        ("s004", "reviewer.md", self.agent_b, "agent b stdout\n", "agent b stderr\n"),
    ]
    for step_name, prompt_name, agent_cmd, stdout_text, stderr_text in expected:
        step_dir = self.session_dir / "run" / step_name
        self.assertEqual((step_dir / "stdout.log").read_text(), stdout_text)
        self.assertEqual((step_dir / "stderr.log").read_text(), stderr_text)
        self.assertEqual((step_dir / "exit_code.txt").read_text(), "0\n")
        effective = (step_dir / "effective_prompt.md").read_text()
        self.assertIn(f"- agent_cmd: {agent_cmd}", effective)
        self.assertIn((self.prompt_dir / prompt_name).read_text(), effective)
    loop_log = (self.session_dir / "run" / "loop" / "loop.log").read_text()
    self.assertIn(f"step=1 prompt={self.prompt_dir / 'builder.md'} agent_cmd={self.agent_a} exit=0", loop_log)
    self.assertIn(f"step=2 prompt={self.prompt_dir / 'reviewer.md'} agent_cmd={self.agent_b} exit=0", loop_log)
    self.assertIn(f"step=3 prompt={self.prompt_dir / 'builder.md'} agent_cmd={self.agent_a} exit=0", loop_log)
    self.assertIn(f"step=4 prompt={self.prompt_dir / 'reviewer.md'} agent_cmd={self.agent_b} exit=0", loop_log)


def test_python_runner_rotates_agent_commands_independently_without_tmux(self) -> None:
    result = self.run_runner(
        [
            "python3",
            "scripts/converge.py",
            "--session-dir",
            str(self.session_dir),
            "--prompt-list",
            str(self.rotation_prompt_list),
            "--agent-cmd",
            str(self.agent_a),
            "--agent-cmd",
            str(self.agent_b),
            "--max-steps",
            "4",
        ]
    )

    self.assert_independent_rotation(result)
```

- [ ] **Step 3: Run the Python non-`tmux` rotation test to establish the red baseline**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_rotates_agent_commands_independently_without_tmux -v`
Expected: FAIL because the current Python runner stores only one `--agent-cmd` value and does not write `- agent_cmd:` into `effective_prompt.md`.

- [ ] **Step 4: Add a failing Python `--tmux` parity test using the same helper**

```python
def test_python_runner_rotates_agent_commands_independently_with_tmux(self) -> None:
    result = self.run_runner(
        [
            "python3",
            "scripts/converge.py",
            "--session-dir",
            str(self.session_dir),
            "--prompt-list",
            str(self.rotation_prompt_list),
            "--agent-cmd",
            str(self.agent_a),
            "--agent-cmd",
            str(self.agent_b),
            "--max-steps",
            "4",
            "--tmux",
        ]
    )

    self.assert_independent_rotation(result)
```

- [ ] **Step 5: Re-run both Python rotation tests and confirm they fail for the same contract gap**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_rotates_agent_commands_independently_without_tmux tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_rotates_agent_commands_independently_with_tmux -v`
Expected: FAIL because both code paths still execute one global command per run.

- [ ] **Step 6: Check the isolated diff before touching runner code**

Run: `jj status`
Expected: `tests/test_converge_tmux.py` is modified and no runner file has changed yet.

Run: `jj diff --git tests/test_converge_tmux.py`
Expected: shows only fixture and Python rotation-test additions.

### Task 2: Implement repeatable `--agent-cmd` in the Python runner

**Files:**
- Modify: `scripts/converge.py`
- Test: `tests/test_converge_tmux.py`

- [ ] **Step 1: Change `argparse` to collect ordered command values while preserving single-command startup output**

```python
ap.add_argument(
    "--agent-cmd",
    action="append",
    required=True,
    help="Agent command, repeat to rotate independently per step.",
)
agent_cmds = args.agent_cmd
print("Starting agent loop")
print(f"session_dir={session_dir}")
print(f"prompt_count={len(prompts)}")
print(f"max_steps={args.max_steps}")
if len(agent_cmds) == 1:
    print(f"agent_cmd={agent_cmds[0]}")
else:
    print(f"agent_cmd_count={len(agent_cmds)}")
```

- [ ] **Step 2: Compute the step-local command and record it in `effective_prompt.md`**

```python
for step in range(1, args.max_steps + 1):
    prompt = prompts[(step - 1) % len(prompts)]
    agent_cmd = agent_cmds[(step - 1) % len(agent_cmds)]
    header = [
        "# Runtime Protocol",
        "",
        f"- step: {step}",
        f"- agent_cmd: {agent_cmd}",
        f"- input_handoff: {input_handoff}" if input_handoff else "- input_handoff: (none)",
        "- read input handoff as latest context." if input_handoff else "- no previous handoff exists for this step.",
        f"- output_handoff: {output_handoff}",
        "- write next handoff content to output_handoff.",
        "- do not modify files outside the task scope.",
        "",
        "# Role Prompt",
        "",
    ]
    effective.write_text("\n".join(header) + prompt.read_text())
```

- [ ] **Step 3: Route the selected command through both execution paths and append it to `loop.log`**

```python
print(f"[step {step}] start prompt={prompt.name} time={start_iso}")
if tmux_session_name:
    write_tmux_step_script(
        step_runner,
        agent_cmd=agent_cmd,
        effective=effective,
        stdout_log=stdout_log,
        stderr_log=stderr_log,
        exit_file=exit_file,
    )
else:
    with effective.open("r") as input_stream, stdout_log.open("w") as out, stderr_log.open("w") as err:
        proc = subprocess.run(["bash", "-lc", agent_cmd], text=True, stdin=input_stream, stdout=out, stderr=err)
    code = proc.returncode
    exit_file.write_text(f"{code}\n")
with loop_log.open("a") as lf:
    lf.write(f"{end_iso} step={step} prompt={prompt} agent_cmd={agent_cmd} exit={code} elapsed_s={elapsed}\n")
```

- [ ] **Step 4: Run the two Python rotation tests and make them pass**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_rotates_agent_commands_independently_without_tmux tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_rotates_agent_commands_independently_with_tmux -v`
Expected: PASS

- [ ] **Step 5: Run the existing Python single-command regression tests**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_without_tmux_still_writes_logs tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_tmux_mode_keeps_live_output_and_logs tests.test_converge_tmux.ConvergeTmuxTests.test_python_runner_tmux_mode_preserves_each_step_window -v`
Expected: PASS

- [ ] **Step 6: Check the Python-only diff before broadening to the other runners**

Run: `jj status`
Expected: `scripts/converge.py` and `tests/test_converge_tmux.py` are modified.

Run: `jj diff --git scripts/converge.py tests/test_converge_tmux.py`
Expected: shows only repeatable command parsing, per-step selection, header/log metadata, and the new tests.

### Task 3: Add failing shell and Ruby rotation tests against the same contract

**Files:**
- Modify: `tests/test_converge_tmux.py`
- Test: `tests/test_converge_tmux.py`

- [ ] **Step 1: Add shell rotation tests for direct execution and `--tmux` mode**

```python
def test_shell_runner_rotates_agent_commands_independently_without_tmux(self) -> None:
    result = self.run_runner(
        [
            "bash",
            "scripts/converge.sh",
            "--session-dir",
            str(self.session_dir),
            "--prompt-list",
            str(self.rotation_prompt_list),
            "--agent-cmd",
            str(self.agent_a),
            "--agent-cmd",
            str(self.agent_b),
            "--max-steps",
            "4",
        ]
    )

    self.assert_independent_rotation(result)


def test_shell_runner_rotates_agent_commands_independently_with_tmux(self) -> None:
    result = self.run_runner(
        [
            "bash",
            "scripts/converge.sh",
            "--session-dir",
            str(self.session_dir),
            "--prompt-list",
            str(self.rotation_prompt_list),
            "--agent-cmd",
            str(self.agent_a),
            "--agent-cmd",
            str(self.agent_b),
            "--max-steps",
            "4",
            "--tmux",
        ]
    )

    self.assert_independent_rotation(result)
```

- [ ] **Step 2: Run the shell rotation tests to establish the red baseline**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_shell_runner_rotates_agent_commands_independently_without_tmux tests.test_converge_tmux.ConvergeTmuxTests.test_shell_runner_rotates_agent_commands_independently_with_tmux -v`
Expected: FAIL because the shell runner still overwrites `agent_cmd` and never records the selected command in the runtime header or loop log.

- [ ] **Step 3: Add Ruby rotation tests for direct execution and `--tmux` mode**

```python
def test_ruby_runner_rotates_agent_commands_independently_without_tmux(self) -> None:
    if shutil.which("ruby") is None:
        self.skipTest("ruby is not installed")

    result = self.run_runner(
        [
            "ruby",
            "scripts/converge.rb",
            "--session-dir",
            str(self.session_dir),
            "--prompt-list",
            str(self.rotation_prompt_list),
            "--agent-cmd",
            str(self.agent_a),
            "--agent-cmd",
            str(self.agent_b),
            "--max-steps",
            "4",
        ]
    )

    self.assert_independent_rotation(result)


def test_ruby_runner_rotates_agent_commands_independently_with_tmux(self) -> None:
    if shutil.which("ruby") is None:
        self.skipTest("ruby is not installed")

    result = self.run_runner(
        [
            "ruby",
            "scripts/converge.rb",
            "--session-dir",
            str(self.session_dir),
            "--prompt-list",
            str(self.rotation_prompt_list),
            "--agent-cmd",
            str(self.agent_a),
            "--agent-cmd",
            str(self.agent_b),
            "--max-steps",
            "4",
            "--tmux",
        ]
    )

    self.assert_independent_rotation(result)
```

- [ ] **Step 4: Run the Ruby rotation tests to establish the red baseline**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_ruby_runner_rotates_agent_commands_independently_without_tmux tests.test_converge_tmux.ConvergeTmuxTests.test_ruby_runner_rotates_agent_commands_independently_with_tmux -v`
Expected: FAIL if Ruby is installed, or `skipped` if Ruby is unavailable in the execution environment.

- [ ] **Step 5: Check the test diff before modifying shell or Ruby code**

Run: `jj status`
Expected: only `tests/test_converge_tmux.py` is additionally modified on top of the Python runner work.

Run: `jj diff --git tests/test_converge_tmux.py`
Expected: shows shell and Ruby rotation tests layered onto the shared helper.

### Task 4: Implement repeatable `--agent-cmd` in the shell runner

**Files:**
- Modify: `scripts/converge.sh`
- Test: `tests/test_converge_tmux.py`

- [ ] **Step 1: Parse `--agent-cmd` into an array and preserve the single-command banner**

```bash
session_dir="" prompt_list="" max_steps=10 use_tmux=0 tmux_session_name="" tmux_created=0
agent_cmds=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-dir) session_dir="${2:-}"; shift 2 ;;
    --prompt-list) prompt_list="${2:-}"; shift 2 ;;
    --agent-cmd) agent_cmds+=("${2:-}"); shift 2 ;;
    --max-steps) max_steps="${2:-}"; shift 2 ;;
    --tmux) use_tmux=1; shift ;;
    --tmux-session-name) tmux_session_name="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$session_dir" && -n "$prompt_list" && ${#agent_cmds[@]} -gt 0 ]] || { usage >&2; exit 1; }
[[ -f "$prompt_list" ]] || { echo "Prompt list not found: $prompt_list" >&2; exit 1; }
[[ "$max_steps" =~ ^[0-9]+$ && "$max_steps" -gt 0 ]] || { echo "--max-steps must be a positive integer." >&2; exit 1; }
session_dir="$(mkdir -p "$session_dir" && cd "$session_dir" && pwd)"
prompt_list="$(cd "$(dirname "$prompt_list")" && pwd)/$(basename "$prompt_list")"
if [[ ${#agent_cmds[@]} -eq 1 ]]; then
  echo "agent_cmd=${agent_cmds[0]}"
else
  echo "agent_cmd_count=${#agent_cmds[@]}"
fi
```

- [ ] **Step 2: Compute the step-local command and add it to the runtime header**

```bash
for ((step=1; step<=max_steps; step++)); do
  prompt="${prompts[$(( (step - 1) % ${#prompts[@]} ))]}"
  agent_cmd="${agent_cmds[$(( (step - 1) % ${#agent_cmds[@]} ))]}"
  {
    echo "# Runtime Protocol"; echo
    echo "- step: $step"
    echo "- agent_cmd: $agent_cmd"
    if [[ -n "$input_handoff" ]]; then
      echo "- input_handoff: $input_handoff"
      echo "- read input handoff as latest context."
    else
      echo "- input_handoff: (none)"
      echo "- no previous handoff exists for this step."
    fi
    echo "- output_handoff: $output_handoff"
    echo "- write next handoff content to output_handoff."
    echo "- do not modify files outside the task scope."; echo
    echo "# Role Prompt"; echo
    cat "$prompt"
  } > "$effective"
```

- [ ] **Step 3: Pass the selected command through both execution paths and append it to `loop.log`**

```bash
if [[ "$use_tmux" -eq 1 ]]; then
  write_tmux_step_script "$step_runner" "$effective" "$stdout_log" "$stderr_log" "$exit_file" "$agent_cmd"
else
  set +e
  bash -lc "$agent_cmd" < "$effective" > "$stdout_log" 2> "$stderr_log"
  code=$?
  set -e
  printf '%s\n' "$code" > "$exit_file"
fi
printf '%s step=%d prompt=%s agent_cmd=%s exit=%d elapsed_s=%d\n' \
  "$end_iso" "$step" "$prompt" "$agent_cmd" "$code" "$elapsed" >> "$loop_log"
```

- [ ] **Step 4: Run the shell rotation tests and make them pass**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_shell_runner_rotates_agent_commands_independently_without_tmux tests.test_converge_tmux.ConvergeTmuxTests.test_shell_runner_rotates_agent_commands_independently_with_tmux -v`
Expected: PASS

- [ ] **Step 5: Run the existing shell single-command regression tests**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_shell_runner_tmux_mode_keeps_live_output_and_logs tests.test_converge_tmux.ConvergeTmuxTests.test_shell_runner_tmux_mode_preserves_each_step_window -v`
Expected: PASS

- [ ] **Step 6: Check the shell diff before moving to Ruby**

Run: `jj diff --git scripts/converge.sh tests/test_converge_tmux.py`
Expected: shows only shell parsing, per-step selection, header/log metadata, and the shell rotation tests.

### Task 5: Implement repeatable `--agent-cmd` in the Ruby runner and update docs

**Files:**
- Modify: `scripts/converge.rb`
- Modify: `scripts/converge.md`
- Test: `tests/test_converge_tmux.py`

- [ ] **Step 1: Parse repeated commands into `opts[:agent_cmds]` and preserve the single-command banner**

```ruby
opts = { max_steps: 10, tmux: false, agent_cmds: [] }
i = 0
while i < ARGV.length
  case ARGV[i]
  when "--session-dir" then opts[:session_dir] = ARGV[i + 1]; i += 2
  when "--prompt-list" then opts[:prompt_list] = ARGV[i + 1]; i += 2
  when "--agent-cmd" then opts[:agent_cmds] << ARGV[i + 1]; i += 2
  when "--max-steps" then opts[:max_steps] = Integer(ARGV[i + 1]); i += 2
  when "--tmux" then opts[:tmux] = true; i += 1
  when "--tmux-session-name" then opts[:tmux_session_name] = ARGV[i + 1]; i += 2
  when "-h", "--help" then usage; exit 0
  else
    warn "Unknown argument: #{ARGV[i]}"
    usage
    exit 1
  end
end
if opts[:session_dir].to_s.empty? || opts[:prompt_list].to_s.empty? || opts[:agent_cmds].empty?
  usage
  exit 1
end
if opts[:agent_cmds].length == 1
  puts "agent_cmd=#{opts[:agent_cmds].first}"
else
  puts "agent_cmd_count=#{opts[:agent_cmds].length}"
end
```

- [ ] **Step 2: Compute the step-local command and record it in the runtime header and loop log**

```ruby
1.upto(opts[:max_steps]) do |step|
  prompt = prompts[(step - 1) % prompts.length]
  agent_cmd = opts[:agent_cmds][(step - 1) % opts[:agent_cmds].length]
  header = []
  header << "# Runtime Protocol"
  header << ""
  header << "- step: #{step}"
  header << "- agent_cmd: #{agent_cmd}"
  if input_handoff
    header << "- input_handoff: #{input_handoff}"
    header << "- read input handoff as latest context."
  else
    header << "- input_handoff: (none)"
    header << "- no previous handoff exists for this step."
  end
  header << "- output_handoff: #{output_handoff}"
  header << "- write next handoff content to output_handoff."
  header << "- do not modify files outside the task scope."
  header << ""
  header << "# Role Prompt"
  header << ""
  File.write(effective, header.join("\n") + File.read(prompt))
  if opts[:tmux]
    write_tmux_step_script(
      step_runner,
      agent_cmd: agent_cmd,
      effective: effective,
      stdout_log: stdout_log,
      stderr_log: stderr_log,
      exit_file: exit_file
    )
  else
    File.open(effective, "r") do |input|
      File.open(stdout_log, "w") do |output|
        File.open(stderr_log, "w") do |error|
          system("bash", "-lc", agent_cmd, in: input, out: output, err: error)
          code = $?.exitstatus
          File.write(exit_file, "#{code}\n")
        end
      end
    end
  end
  File.open(loop_log, "a") do |f|
    f.puts("#{iso_now} step=#{step} prompt=#{prompt} agent_cmd=#{agent_cmd} exit=#{code} elapsed_s=#{elapsed}")
  end
end
```

- [ ] **Step 3: Update the docs to describe repeated `--agent-cmd` and independent rotation**

```md
### Independent command rotation

- `--agent-cmd` may be passed multiple times.
- Prompts rotate from `--prompt-list`; commands rotate independently from repeated `--agent-cmd`.
- `effective_prompt.md` includes the selected `agent_cmd` for each step.
- `run/loop/loop.log` records `agent_cmd=` for each step.
```

```bash
python3 ./scripts/converge.py \
  --session-dir ./tmp/session-a \
  --prompt-list ./tmp/prompts.txt \
  --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" \
  --agent-cmd "claude -p --permission-mode bypassPermissions" \
  --max-steps 4
```

- [ ] **Step 4: Run the Ruby rotation tests and make them pass**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_ruby_runner_rotates_agent_commands_independently_without_tmux tests.test_converge_tmux.ConvergeTmuxTests.test_ruby_runner_rotates_agent_commands_independently_with_tmux -v`
Expected: PASS if Ruby is installed, or `skipped` if Ruby is unavailable.

- [ ] **Step 5: Run the existing Ruby single-command regression tests**

Run: `python3 -m unittest tests.test_converge_tmux.ConvergeTmuxTests.test_ruby_runner_tmux_mode_keeps_live_output_and_logs tests.test_converge_tmux.ConvergeTmuxTests.test_ruby_runner_tmux_mode_preserves_each_step_window tests.test_converge_tmux.ConvergeTmuxTests.test_ruby_runner_without_tmux_redirects_entire_shell_snippet -v`
Expected: PASS if Ruby is installed, or `skipped` only for the Ruby-specific cases when Ruby is unavailable.

- [ ] **Step 6: Run the full converge runner test suite**

Run: `python3 -m unittest tests.test_converge_tmux -v`
Expected: PASS, with Ruby-specific tests skipped only if Ruby is unavailable.

- [ ] **Step 7: Review the final diff and repo state**

Run: `jj status`
Expected: modified files are limited to `scripts/converge.py`, `scripts/converge.sh`, `scripts/converge.rb`, `scripts/converge.md`, and `tests/test_converge_tmux.py`.

Run: `jj diff --git scripts/converge.py scripts/converge.sh scripts/converge.rb scripts/converge.md tests/test_converge_tmux.py`
Expected: shows the repeatable command contract, per-step audit metadata, and the new black-box tests only.
