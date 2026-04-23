# Converge Run-To-Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--run-to-completion` to `scripts/converge.sh` so the shell converge loop can stop before `--max-steps` after two consecutive whole-work `complete` judgements emitted through handoff files.

**Architecture:** Keep `--max-steps` as the hard ceiling and layer run-to-completion on top of the existing handoff artifact flow. The shell runner will persist the new mode in run metadata, teach agents to emit YAML frontmatter in `handoff.md`, recompute a trailing completion streak on `resume`, and stop early only after two consecutive `complete` judgements. Missing or malformed handoff judgements are treated as non-fatal `incomplete` signals so the safe fallback is to continue the loop.

**Tech Stack:** POSIX shell, Bash arrays/functions, Bats, Markdown docs

---

## File Structure

- `tests/converge_sh.bats`: black-box CLI contract, fake agent helpers, run-to-completion regression tests, and resume coverage.
- `scripts/converge.sh`: CLI parsing, metadata persistence, handoff judgement parsing, runtime protocol text, loop logging, and early-stop/resume control flow.
- `scripts/converge.md`: usage docs, runtime protocol contract, handoff frontmatter format, and resume behavior.

## Execution Notes

- This repo uses `jj`; use `jj status` and `jj diff --git` for checkpoints and `jj commit` for the final green commit.
- Keep scope limited to the shell runner and its Bats contract. Do not introduce a sidecar completion artifact or any Python/Ruby changes.
- Stay in TDD order: tests first, verify red, implement minimally, verify green, then update docs.

### Task 1: Lock the CLI contract with failing Bats tests

**Files:**
- Modify: `tests/converge_sh.bats`
- Test: `tests/converge_sh.bats`

- [ ] **Step 1: Add a reusable fake agent that emits sequenced handoff judgements**

```bash
make_sequence_handoff_agent() {
  local path="$1"
  local sequence_file="$2"
  local count_file="$3"

  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
payload="\$(cat)"
output_handoff="\$(printf '%s\n' "\$payload" | awk -F': ' '/^- output_handoff:/ { print \$2; exit }')"
count=0
if [[ -f "$count_file" ]]; then
  count="\$(<"$count_file")"
fi
count=\$((count + 1))
printf '%s\n' "\$count" > "$count_file"
judgement="\$(sed -n "\${count}p" "$sequence_file")"

case "\$judgement" in
  complete|incomplete)
    cat > "\$output_handoff" <<HANDOFF
---
converge_work_judgement: \$judgement
converge_reason: scripted-\$judgement-step-\$count
---

Step \$count handoff body.
HANDOFF
    ;;
  malformed)
    cat > "\$output_handoff" <<HANDOFF
---
converge_work_judgement: maybe
---

Malformed handoff body.
HANDOFF
    ;;
  missing)
    : > "\$output_handoff"
    ;;
  *)
    echo "Unknown judgement: \$judgement" >&2
    exit 1
    ;;
esac

printf 'agent-step-%s\n' "\$count"
EOF
  chmod +x "$path"
}
```

Place this helper below `make_agent()` so the later tests can share one deterministic fixture for `complete`, `incomplete`, `missing`, and `malformed` handoffs.

- [ ] **Step 2: Add failing CLI validation tests for the new flag**

```bash
@test "rejects --run-to-completion without session dir" {
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2 \
    --run-to-completion

  [ "$status" -ne 0 ]
  [[ "$output" == *"--run-to-completion requires --session-dir."* ]]
}

@test "rejects --run-to-completion when handoff is disabled" {
  session_dir="$TEST_ROOT/session"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2 \
    --no-handoff \
    --run-to-completion

  [ "$status" -ne 0 ]
  [[ "$output" == *"--run-to-completion requires handoff mode; remove --no-handoff."* ]]
}
```

- [ ] **Step 3: Add a failing dry-run visibility test for completion mode**

```bash
@test "dry run prints run-to-completion mode and streak target" {
  session_dir="$TEST_ROOT/session"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 3 \
    --run-to-completion \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"completion_mode=run_to_completion"* ]]
  [[ "$output" == *"completion_streak_target=2"* ]]
}
```

- [ ] **Step 4: Run the three new CLI tests to establish the red baseline**

Run: `bats tests/converge_sh.bats --filter 'rejects --run-to-completion|dry run prints run-to-completion mode and streak target'`
Expected: FAIL because `scripts/converge.sh` does not accept `--run-to-completion` yet and therefore cannot validate or print the new mode.

- [ ] **Step 5: Check the isolated test-only diff before touching the runner**

Run: `jj status`
Expected: only `tests/converge_sh.bats` is modified.

Run: `jj diff --git tests/converge_sh.bats`
Expected: shows the helper plus only the three new run-to-completion CLI tests.

### Task 2: Lock early-stop and resume behavior with failing Bats tests

**Files:**
- Modify: `tests/converge_sh.bats`
- Test: `tests/converge_sh.bats`

- [ ] **Step 1: Add a failing test for early stop after two consecutive complete judgements**

```bash
@test "--run-to-completion stops after two consecutive complete judgements" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'complete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_handoff_agent "$agent_path" "$sequence_file" "$count_file"

  run bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 5 \
    --run-to-completion

  [ "$status" -eq 0 ]
  [[ "$output" == *"Completion confirmed at step 2 after 2 consecutive complete judgements."* ]]
  [[ "$output" == *"Loop finished after 2 executed steps."* ]]
  [ -f "$session_dir/run/s002/exit_code.txt" ]
  [ ! -e "$session_dir/run/s003/exit_code.txt" ]
  [[ "$(<"$session_dir/run/s001/effective_prompt.md")" == *"completion_mode: run_to_completion"* ]]
  [[ "$(<"$session_dir/run/s001/effective_prompt.md")" == *"converge_work_judgement: complete|incomplete"* ]]
  [[ "$(<"$session_dir/run/loop/loop.log")" == *"completion_judgement=complete completion_streak=2/2"* ]]
}
```

- [ ] **Step 2: Add failing tests for streak reset and malformed-or-missing fallback**

```bash
@test "incomplete judgement resets the completion streak" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'complete\nincomplete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_handoff_agent "$agent_path" "$sequence_file" "$count_file"

  run bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 5 \
    --run-to-completion

  [ "$status" -eq 0 ]
  [[ "$output" == *"Completion confirmed at step 4 after 2 consecutive complete judgements."* ]]
  [ -f "$session_dir/run/s004/exit_code.txt" ]
  [ ! -e "$session_dir/run/s005/exit_code.txt" ]
  [[ "$(<"$session_dir/run/loop/loop.log")" == *"completion_judgement=incomplete completion_streak=0/2"* ]]
}

@test "missing or malformed completion judgement is treated as incomplete" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'malformed\nmissing\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_handoff_agent "$agent_path" "$sequence_file" "$count_file"

  run bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 5 \
    --run-to-completion

  [ "$status" -eq 0 ]
  [[ "$output" == *"Completion confirmed at step 4 after 2 consecutive complete judgements."* ]]
  [[ "$(<"$session_dir/run/loop/loop.log")" == *"completion_judgement=missing completion_streak=0/2"* ]]
}
```

- [ ] **Step 3: Add failing resume tests for trailing streak recovery and already-confirmed completion**

```bash
@test "resume recomputes a trailing complete streak and stops after the next complete" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'incomplete\ncomplete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_handoff_agent "$agent_path" "$sequence_file" "$count_file"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2 \
    --run-to-completion
  [ "$status" -eq 0 ]
  [ -f "$session_dir/run/s002/exit_code.txt" ]

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    --max-steps 5

  [ "$status" -eq 0 ]
  [[ "$output" == *"resume_from_step=3"* ]]
  [[ "$output" == *"Completion confirmed at step 3 after 2 consecutive complete judgements."* ]]
  [ -f "$session_dir/run/s003/exit_code.txt" ]
  [ ! -e "$session_dir/run/s004/exit_code.txt" ]
}

@test "resume exits immediately when completion was already confirmed" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'complete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_handoff_agent "$agent_path" "$sequence_file" "$count_file"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 5 \
    --run-to-completion
  [ "$status" -eq 0 ]
  [ -f "$session_dir/run/s002/exit_code.txt" ]
  [ ! -e "$session_dir/run/s003/exit_code.txt" ]

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    --max-steps 5

  [ "$status" -eq 0 ]
  [[ "$output" == *"Completion already confirmed at step 2; no remaining steps to run."* ]]
}
```

- [ ] **Step 4: Run the new completion-behavior tests to confirm they fail for the current gap**

Run: `bats tests/converge_sh.bats --filter 'run-to-completion|resume recomputes a trailing complete streak|resume exits immediately when completion was already confirmed'`
Expected: FAIL because the runner neither parses handoff judgements nor persists/recomputes completion mode.

- [ ] **Step 5: Check the expanded red diff before implementation**

Run: `jj status`
Expected: only `tests/converge_sh.bats` is modified.

Run: `jj diff --git tests/converge_sh.bats`
Expected: shows the sequence helper and the five new behavior tests with no runner changes yet.

### Task 3: Implement CLI parsing, metadata, and handoff judgement helpers in the shell runner

**Files:**
- Modify: `scripts/converge.sh`
- Test: `tests/converge_sh.bats`

- [ ] **Step 1: Add the new flag to usage text, CLI parsing, and top-level state**

```bash
# File protocol (when --session-dir is set):
# - <session-dir>/run/meta/run_to_completion.txt

session_dir="" max_steps=10 use_tmux=0 tmux_cleanup=0 tmux_session_name="" tmux_session_name_requested="" tmux_created=0 handoff_disabled=0
run_to_completion=0
completion_streak_target=2
completion_streak=0
current_completion_judgement=""

  --run-to-completion  Stop early after 2 consecutive complete handoff judgements.

    -p|--prompt|-f|--prompt-file|-a|--agent-cmd|-A|--agent-preset|--run-to-completion|-t|--tmux|-x|--tmux-cleanup|-T|--tmux-session-name|-H|--no-handoff)
      if [[ "$mode" == "resume" ]]; then
        echo "resume only accepts -s/--session-dir, -n/--max-steps, and -d/--dry-run." >&2
        exit 1
      fi
      case "$1" in
        -p|--prompt)
          cli_prompt_kinds+=("inline")
          cli_prompt_values+=("${2:-}")
          shift 2
          ;;
        -f|--prompt-file)
          cli_prompt_kinds+=("file")
          cli_prompt_values+=("${2:-}")
          shift 2
          ;;
        -a|--agent-cmd)
          agent_cmds+=("${2:-}")
          shift 2
          ;;
        -A|--agent-preset)
          preset="${2:-}"
          [[ -n "$preset" ]] || { echo "--agent-preset requires a non-empty value." >&2; exit 1; }
          agent_cmds+=("$(agent_preset_command "$preset")")
          shift 2
          ;;
        --run-to-completion) run_to_completion=1; shift ;;
        -t|--tmux) use_tmux=1; shift ;;
        -x|--tmux-cleanup) tmux_cleanup=1; shift ;;
        -T|--tmux-session-name) tmux_session_name_requested="${2:-}"; shift 2 ;;
        -H|--no-handoff) handoff_disabled=1; shift ;;
      esac
```

- [ ] **Step 2: Persist and reload the completion mode in run metadata**

```bash
write_run_metadata() {
  local meta_dir="$1"
  mkdir -p "$meta_dir"
  printf '%s\n' "$max_steps" > "$meta_dir/max_steps.txt"
  printf '%s\n' "$handoff_enabled" > "$meta_dir/handoff_enabled.txt"
  printf '%s\n' "$run_to_completion" > "$meta_dir/run_to_completion.txt"
  printf '%s\n' "$use_tmux" > "$meta_dir/use_tmux.txt"
  printf '%s\n' "$tmux_cleanup" > "$meta_dir/tmux_cleanup.txt"
  printf '%s\n' "$tmux_session_name_requested" > "$meta_dir/tmux_session_name.txt"
  : > "$meta_dir/prompts.tsv"
  : > "$meta_dir/agent_cmds.txt"
}

load_run_metadata() {
  local meta_dir="$1"
  [[ -f "$meta_dir/run_to_completion.txt" ]] || { echo "Cannot resume: missing $meta_dir/run_to_completion.txt" >&2; exit 1; }
  [[ -f "$meta_dir/max_steps.txt" ]] || { echo "Cannot resume: missing $meta_dir/max_steps.txt" >&2; exit 1; }
  [[ -f "$meta_dir/handoff_enabled.txt" ]] || { echo "Cannot resume: missing $meta_dir/handoff_enabled.txt" >&2; exit 1; }
  [[ -f "$meta_dir/use_tmux.txt" ]] || { echo "Cannot resume: missing $meta_dir/use_tmux.txt" >&2; exit 1; }
  run_to_completion="$(<"$meta_dir/run_to_completion.txt")"
  [[ "$run_to_completion" =~ ^[01]$ ]] || { echo "Invalid stored run-to-completion flag: $run_to_completion" >&2; exit 1; }
}
```

- [ ] **Step 3: Add validation, dry-run visibility, and startup visibility for the new mode**

```bash
if [[ "$run_to_completion" -eq 1 && -z "$session_dir" ]]; then
  echo "--run-to-completion requires --session-dir." >&2
  exit 1
fi
if [[ "$run_to_completion" -eq 1 && "$handoff_enabled" -eq 0 ]]; then
  echo "--run-to-completion requires handoff mode; remove --no-handoff." >&2
  exit 1
fi

print_plan() {
  local start_step="$1" end_step="$2"
  local step input_handoff output_handoff
  echo "Dry run plan"
  echo "mode=$mode"
  [[ -n "$session_dir" ]] && echo "session_dir=$session_dir"
  echo "start_step=$start_step"
  echo "max_steps=$end_step"
  echo "prompt_count=${#prompt_values[@]}"
  echo "agent_cmd_count=${#agent_cmds[@]}"
  if [[ "$run_to_completion" -eq 1 ]]; then
    echo "completion_mode=run_to_completion"
    echo "completion_streak_target=$completion_streak_target"
  else
    echo "completion_mode=fixed_steps"
  fi
}

echo "max_steps=$max_steps"
if [[ "$run_to_completion" -eq 1 ]]; then
  echo "completion_mode=run_to_completion"
  echo "completion_streak_target=$completion_streak_target"
else
  echo "completion_mode=fixed_steps"
fi
```

- [ ] **Step 4: Add explicit handoff-frontmatter parsing and streak recomputation helpers**

```bash
parse_handoff_judgement() {
  local handoff_path="$1" line judgement="" in_frontmatter=0
  parsed_completion_judgement=""
  [[ -f "$handoff_path" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_frontmatter" -eq 0 ]]; then
      [[ "$line" == "---" ]] || return 0
      in_frontmatter=1
      continue
    fi
    [[ "$line" == "---" ]] && break
    case "$line" in
      converge_work_judgement:*)
        judgement="${line#converge_work_judgement:}"
        judgement="$(printf '%s' "$judgement" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        ;;
    esac
  done < "$handoff_path"
  case "$judgement" in
    complete|incomplete) parsed_completion_judgement="$judgement" ;;
    *) parsed_completion_judgement="" ;;
  esac
}

recompute_completion_streak() {
  local root="$1" last_step="$2" step handoff_path
  completion_streak=0
  for ((step=last_step; step>=1; step--)); do
    handoff_path="$(printf '%s/s%03d/handoff.md' "$root" "$step")"
    parse_handoff_judgement "$handoff_path"
    if [[ "$parsed_completion_judgement" == "complete" ]]; then
      completion_streak=$((completion_streak + 1))
    else
      break
    fi
  done
}
```

- [ ] **Step 5: Add the run-to-completion protocol text to `effective_prompt.md`**

```bash
emit_effective_prompt() {
  local step="$1" agent_cmd="$2" input_handoff="$3" output_handoff="$4" prompt_kind="$5" prompt_value="$6"
  echo "# Runtime Protocol"
  echo
  echo "- step: $step"
  echo "- agent_cmd: $agent_cmd"
  if [[ "$run_to_completion" -eq 1 ]]; then
    echo "- completion_mode: run_to_completion"
    echo "- completion_streak_target: $completion_streak_target"
    echo "- write YAML frontmatter to output_handoff with converge_work_judgement: complete|incomplete."
    echo "- use complete only if the entire assignment appears finished and the loop should stop if the next step independently agrees."
    echo "- use incomplete if any implementation, review, verification, or uncertainty remains."
  fi
  if [[ -n "$output_handoff" ]]; then
    if [[ -n "$input_handoff" ]]; then
      echo "- input_handoff: $input_handoff"
      echo "- read input handoff as latest context."
    else
      echo "- input_handoff: (none)"
      echo "- no previous handoff exists for this step."
    fi
    echo "- output_handoff: $output_handoff"
    echo "- write next handoff content to output_handoff."
  fi
  echo "- do not modify files outside the task scope."
  echo
  echo "# Role Prompt"
}
```

- [ ] **Step 6: Run the CLI-focused tests and keep the behavior tests red**

Run: `bats tests/converge_sh.bats --filter 'rejects --run-to-completion|dry run prints run-to-completion mode and streak target'`
Expected: PASS

Run: `bats tests/converge_sh.bats --filter 'stops after two consecutive complete judgements|resume recomputes a trailing complete streak'`
Expected: FAIL because the loop still does not update streaks or stop early.

### Task 4: Wire early-stop control flow, resume short-circuiting, and docs

**Files:**
- Modify: `scripts/converge.sh`
- Modify: `scripts/converge.md`
- Test: `tests/converge_sh.bats`

- [ ] **Step 1: Recompute resume state before the loop and short-circuit when completion is already confirmed**

```bash
if [[ "$mode" == "resume" && "$run_to_completion" -eq 1 ]]; then
  recompute_completion_streak "$run_dir" "$last_completed_step"
  if (( completion_streak >= completion_streak_target )); then
    echo "Starting agent loop (mode=$mode)"
    echo "session_dir=$session_dir"
    echo "prompt_count=${#prompt_values[@]}"
    echo "max_steps=$max_steps"
    echo "resume_from_step=$start_step"
    echo "completion_mode=run_to_completion"
    echo "completion_streak_target=$completion_streak_target"
    echo "Completion already confirmed at step $last_completed_step; no remaining steps to run."
    exit 0
  fi
fi
```

- [ ] **Step 2: Update the live loop to track the parsed judgement, append it to `loop.log`, and break after a confirmed streak**

```bash
record_step_completion_state() {
  local handoff_path="$1"
  parse_handoff_judgement "$handoff_path"
  case "$parsed_completion_judgement" in
    complete)
      current_completion_judgement="complete"
      completion_streak=$((completion_streak + 1))
      ;;
    incomplete)
      current_completion_judgement="incomplete"
      completion_streak=0
      ;;
    *)
      current_completion_judgement="missing"
      completion_streak=0
      ;;
  esac
}

completed_steps=0
for ((step=start_step; step<=max_steps; step++)); do
  resolve_step_context "$step"
  prompt_kind="$step_prompt_kind"
  prompt_value="$step_prompt_value"
  prompt_label="$step_prompt_label"
  agent_cmd="$step_agent_cmd"
  compute_handoff_paths "$step"
  input_handoff="$step_input_handoff"
  output_handoff="$step_output_handoff"
  completed_steps=$((completed_steps + 1))
  if [[ "$run_to_completion" -eq 1 ]]; then
    record_step_completion_state "$output_handoff"
    echo "completion_judgement=$current_completion_judgement streak=${completion_streak}/${completion_streak_target}"
  fi
  if [[ -n "$loop_log" ]]; then
    if [[ "$run_to_completion" -eq 1 ]]; then
      printf '%s step=%d prompt=%s agent_cmd=%q exit=%d elapsed_s=%d completion_judgement=%s completion_streak=%d/%d\n' \
        "$end_iso" "$step" "$prompt_label" "$agent_cmd" "$code" "$elapsed" "$current_completion_judgement" "$completion_streak" "$completion_streak_target" >> "$loop_log"
    else
      printf '%s step=%d prompt=%s agent_cmd=%q exit=%d elapsed_s=%d\n' \
        "$end_iso" "$step" "$prompt_label" "$agent_cmd" "$code" "$elapsed" >> "$loop_log"
    fi
  fi
  if [[ "$run_to_completion" -eq 1 && "$completion_streak" -ge "$completion_streak_target" ]]; then
    echo "Completion confirmed at step $step after $completion_streak_target consecutive complete judgements."
    break
  fi
done

echo "Loop finished after $completed_steps executed steps."
```

- [ ] **Step 3: Update the docs with the new flag, frontmatter contract, and resume behavior**

````md
### Run until work completion is confirmed

```bash
./scripts/converge.sh run \
  --session-dir ./tmp/session-a \
  --prompt-file ./tmp/prompts/builder.md \
  --prompt-file ./tmp/prompts/reviewer.md \
  --agent-preset codex \
  --max-steps 10 \
  --run-to-completion
```

- `--run-to-completion` requires `--session-dir` and handoff mode.
- The runner stops early only after two consecutive `complete` judgements.
- Each `handoff.md` must begin with YAML frontmatter:

```md
---
converge_work_judgement: complete
converge_reason: all requested work is finished
---
```
````

Add these exact bullets to the surrounding sections as well:

- Runtime protocol:
  - `completion_mode`
  - `completion_streak_target`
  - YAML frontmatter instructions for `converge_work_judgement`
- Artifacts:
  - `<session-dir>/run/meta/run_to_completion.txt`
  - `loop.log` includes `completion_judgement` and `completion_streak` when the mode is enabled
- Resume:
  - `resume` inherits stored completion mode
  - if the stored run already ended with two trailing `complete` judgements, `resume` exits immediately

- [ ] **Step 4: Run the focused completion suite and make it pass**

Run: `bats tests/converge_sh.bats --filter 'run-to-completion|resume recomputes a trailing complete streak|resume exits immediately when completion was already confirmed'`
Expected: PASS

- [ ] **Step 5: Run the full shell contract suite**

Run: `bats tests/converge_sh.bats`
Expected: PASS

- [ ] **Step 6: Review the final diff and commit the green change**

Run: `jj status`
Expected: `scripts/converge.sh`, `scripts/converge.md`, and `tests/converge_sh.bats` are modified.

Run: `jj diff --git`
Expected: shows only the run-to-completion CLI/docs/tests/runner changes described above.

Run: `jj commit -m "Add converge run-to-completion mode"`
Expected: commit succeeds with the tested shell runner changes.
