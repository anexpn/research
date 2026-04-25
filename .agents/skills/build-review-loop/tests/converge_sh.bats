#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT_PATH="$REPO_ROOT/scripts/converge.sh"
  TEST_ROOT="$(mktemp -d)"
  BIN_DIR="$TEST_ROOT/bin"
  PROMPT_DIR="$TEST_ROOT/prompts"
  mkdir -p "$BIN_DIR" "$PROMPT_DIR"

  cat > "$PROMPT_DIR/builder.md" <<'EOF'
Builder prompt body.
EOF
  cat > "$PROMPT_DIR/reviewer.md" <<'EOF'
Reviewer prompt body.
EOF
}

teardown() {
  rm -rf "$TEST_ROOT"
}

make_agent() {
  local path="$1"
  local stdout_text="$2"
  local stderr_text="${3:-}"
  local exit_code="${4:-0}"

  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf '%s' '$stdout_text'
printf '%s' '$stderr_text' >&2
exit $exit_code
EOF
  chmod +x "$path"
}

make_sequence_completion_agent() {
  local path="$1"
  local sequence_file="$2"
  local count_file="$3"

  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
payload="\$(cat)"
output_completion="\$(printf '%s\n' "\$payload" | awk -F': ' '/^- output_completion:/ { print \$2; exit }')"
output_handoff="\$(printf '%s\n' "\$payload" | awk -F': ' '/^- output_handoff:/ { print \$2; exit }')"
[[ -n "\$output_completion" ]] || {
  echo "Missing output_completion path" >&2
  exit 1
}
count=0
if [[ -f "$count_file" ]]; then
  count="\$(<"$count_file")"
fi
count=\$((count + 1))
printf '%s\n' "\$count" > "$count_file"
judgement="\$(sed -n "\${count}p" "$sequence_file")"

case "\$judgement" in
  complete|incomplete)
    printf '%s\n' "\$judgement" > "\$output_completion"
    if [[ -n "\$output_handoff" ]]; then
      cat > "\$output_handoff" <<HANDOFF
Step \$count handoff body.
HANDOFF
    fi
    ;;
  malformed)
    printf '%s\n' 'maybe later' > "\$output_completion"
    ;;
  missing)
    : > "\$output_completion"
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

make_fake_tmux() {
  local tmux_path="$BIN_DIR/tmux"
  cat > "$tmux_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

root="${FAKE_TMUX_ROOT:?FAKE_TMUX_ROOT is required}"
mkdir -p "$root/sessions" "$root/panes" "$root/waitfor"

sanitize() {
  local name="$1"
  name="${name//\//_}"
  name="${name//:/__}"
  printf '%s\n' "$name"
}

status_path_for_target() {
  local target
  target="$(sanitize "$1")"
  printf '%s/panes/%s.status\n' "$root" "$target"
}

stdout_path_for_target() {
  local target
  target="$(sanitize "$1")"
  printf '%s/panes/%s.stdout\n' "$root" "$target"
}

stderr_path_for_target() {
  local target
  target="$(sanitize "$1")"
  printf '%s/panes/%s.stderr\n' "$root" "$target"
}

waitfor_path_for_channel() {
  local channel
  channel="$(sanitize "$1")"
  printf '%s/waitfor/%s.signal\n' "$root" "$channel"
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  exit 1
fi
shift

case "$cmd" in
  has-session)
    target=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ -f "$root/sessions/$target" ]]
    ;;
  kill-session)
    target=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    rm -f "$root/sessions/$target"
    ;;
  set-option)
    exit 0
    ;;
  list-panes)
    target=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ -f "$(status_path_for_target "$target")" ]]; then
      printf '1\n'
    else
      printf '0\n'
    fi
    ;;
  display-message)
    target=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t) target="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    cat "$(status_path_for_target "$target")"
    ;;
  wait-for)
    signal_mode=0
    channel=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -S)
          signal_mode=1
          channel="$2"
          shift 2
          ;;
        *)
          channel="$1"
          shift
          ;;
      esac
    done
    [[ -n "$channel" ]] || exit 1
    signal_path="$(waitfor_path_for_channel "$channel")"
    if [[ "$signal_mode" -eq 1 ]]; then
      : > "$signal_path"
      exit 0
    fi
    for _ in $(seq 1 500); do
      if [[ -f "$signal_path" ]]; then
        exit 0
      fi
      sleep 0.01
    done
    exit 1
    ;;
  new-session|new-window)
    session=""
    target=""
    window_name="default"
    pane_cmd=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -s) session="$2"; shift 2 ;;
        -t) target="$2"; shift 2 ;;
        -n) window_name="$2"; shift 2 ;;
        -d) shift ;;
        *)
          pane_cmd=("$@")
          break
          ;;
      esac
    done

    if [[ -z "$session" ]]; then
      session="$target"
    fi

    : > "$root/sessions/$session"
    pane_target="${session}:${window_name}"
    if [[ ${#pane_cmd[@]} -gt 0 ]]; then
      stdout_path="$(stdout_path_for_target "$pane_target")"
      stderr_path="$(stderr_path_for_target "$pane_target")"
      (
        if "${pane_cmd[@]}" >"$stdout_path" 2>"$stderr_path"; then
          code=0
        else
          code=$?
        fi
        printf '%s\n' "$code" > "$(status_path_for_target "$pane_target")"
      ) &
    else
      printf '0\n' > "$(status_path_for_target "$pane_target")"
    fi
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$tmux_path"
}

@test "fails when required arguments are missing" {
  run bash "$SCRIPT_PATH"
  [ "$status" -ne 0 ]
  [[ "$output" == *"USAGE"* ]]
}

@test "rejects unknown arguments" {
  run bash "$SCRIPT_PATH" --not-a-real-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown argument: --not-a-real-flag"* ]]
  [[ "$output" == *"USAGE"* ]]
}

@test "rejects non-positive max steps" {
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 0

  [ "$status" -ne 0 ]
  [[ "$output" == *"--max-steps must be a positive integer."* ]]
}

@test "rejects non-numeric max steps" {
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps nope

  [ "$status" -ne 0 ]
  [[ "$output" == *"--max-steps must be a positive integer."* ]]
}

@test "rejects empty agent command" {
  run bash "$SCRIPT_PATH" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd ""

  [ "$status" -ne 0 ]
  [[ "$output" == *"--agent-cmd requires a non-empty value."* ]]
}

@test "fails when prompt file path is missing" {
  run bash "$SCRIPT_PATH" \
    --prompt-file "$TEST_ROOT/missing-prompt.md" \
    --agent-cmd "$BIN_DIR/agent"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Prompt file not found:"* ]]
}

@test "fails when prompt value is empty" {
  run bash "$SCRIPT_PATH" \
    --prompt "" \
    --agent-cmd "$BIN_DIR/agent"

  [ "$status" -ne 0 ]
  [[ "$output" == *"--prompt requires a non-empty value."* ]]
}

@test "fails when prompt-file value is empty" {
  run bash "$SCRIPT_PATH" \
    --prompt-file "" \
    --agent-cmd "$BIN_DIR/agent"

  [ "$status" -ne 0 ]
  [[ "$output" == *"--prompt-file requires a non-empty value."* ]]
}

@test "stores inline prompts as session snapshot files for resume" {
  session_dir="$TEST_ROOT/session"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt "Inline builder body." \
    --agent-cmd /bin/cat \
    --max-steps 1 \
    --no-handoff

  [ "$status" -eq 0 ]
  [ -d "$session_dir/run/meta/prompts" ]
  prompts_meta="$(<"$session_dir/run/meta/prompts.tsv")"
  [[ "$prompts_meta" == *"$session_dir/run/meta/prompts/"* ]]
  [[ "$prompts_meta" != *$'inline\tInline builder body.'* ]]

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    --additional-steps 1

  [ "$status" -eq 0 ]
  [[ "$(<"$session_dir/run/s002/stdout.log")" == *"Inline builder body."* ]]
}

@test "copies prompt files into the session so resume does not depend on the original path" {
  session_dir="$TEST_ROOT/session"
  prompt_file="$PROMPT_DIR/builder.md"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$prompt_file" \
    --agent-cmd /bin/cat \
    --max-steps 1 \
    --no-handoff

  [ "$status" -eq 0 ]
  [ -d "$session_dir/run/meta/prompts" ]
  rm "$prompt_file"

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    --additional-steps 1

  [ "$status" -eq 0 ]
  [[ "$(<"$session_dir/run/s002/stdout.log")" == *"Builder prompt body."* ]]
}

@test "defaults session dir to a temp folder and writes run artifacts" {
  agent_a="$BIN_DIR/agent-a"
  agent_b="$BIN_DIR/agent-b"
  tmp_root="$TEST_ROOT/tmp"
  mkdir -p "$tmp_root"
  make_agent "$agent_a" "agent-a\n"
  make_agent "$agent_b" "agent-b\n"

  run env TMPDIR="$tmp_root" bash "$SCRIPT_PATH" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --prompt-file "$PROMPT_DIR/reviewer.md" \
    --agent-cmd "$agent_a" \
    --agent-cmd "$agent_b" \
    --max-steps 3

  [ "$status" -eq 0 ]
  session_dir="$(printf '%s\n' "$output" | awk -F= '/^session_dir=/{print $2; exit}')"
  [[ "$session_dir" == "$tmp_root"/converge-session.* ]]
  [[ "$output" == *"Starting agent loop"* ]]
  [[ "$output" == *"prompt_count=2"* ]]
  [[ "$output" == *"agent-a"* ]]
  [[ "$output" == *"agent-b"* ]]
  [[ "$output" == *"[step 3] done exit=0"* ]]
  [ -d "$session_dir/run" ]
  [ -f "$session_dir/run/s001/stdout.log" ]
  [ -f "$session_dir/run/s002/stdout.log" ]
  [ -f "$session_dir/run/s003/stdout.log" ]
  [[ "$(<"$session_dir/run/s001/stdout.log")" == *"agent-a"* ]]
  [[ "$(<"$session_dir/run/s002/stdout.log")" == *"agent-b"* ]]
  [[ "$(<"$session_dir/run/s003/stdout.log")" == *"agent-a"* ]]
}

@test "--no-session-dir preserves no-artifact mode" {
  agent_a="$BIN_DIR/agent-a"
  agent_b="$BIN_DIR/agent-b"
  tmp_root="$TEST_ROOT/tmp"
  mkdir -p "$tmp_root"
  make_agent "$agent_a" "agent-a\n"
  make_agent "$agent_b" "agent-b\n"

  run env TMPDIR="$tmp_root" bash "$SCRIPT_PATH" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --prompt-file "$PROMPT_DIR/reviewer.md" \
    --agent-cmd "$agent_a" \
    --agent-cmd "$agent_b" \
    --max-steps 3 \
    --no-session-dir

  [ "$status" -eq 0 ]
  [[ "$output" != *"session_dir="* ]]
  [[ "$output" == *"agent-a"* ]]
  [[ "$output" == *"agent-b"* ]]
  [ -z "$(find "$tmp_root" -maxdepth 1 -name 'converge-session.*' -print -quit)" ]
}

@test "dry run prints plan and does not execute agents" {
  agent_path="$BIN_DIR/agent"
  marker="$TEST_ROOT/executed.marker"
  cat > "$agent_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
touch "$marker"
EOF
  chmod +x "$agent_path"

  run bash "$SCRIPT_PATH" run \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2 \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run plan"* ]]
  [[ "$output" == *"[step 1]"* ]]
  [[ "$output" == *"[step 2]"* ]]
  [ ! -f "$marker" ]
}

@test "rejects --run-to-completion when session storage is disabled" {
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2 \
    --no-session-dir \
    --run-to-completion

  [ "$status" -ne 0 ]
  [[ "$output" == *"--run-to-completion requires session storage; remove --no-session-dir."* ]]
}

@test "--run-to-completion works when handoff is disabled" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'complete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_completion_agent "$agent_path" "$sequence_file" "$count_file"

  run bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 5 \
    --no-handoff \
    --run-to-completion

  [ "$status" -eq 0 ]
  [[ "$output" == *"Completion confirmed at step 2 after 2 consecutive complete judgements."* ]]
  [ -f "$session_dir/run/s001/completion_status.txt" ]
  [ ! -e "$session_dir/run/s001/handoff.md" ]
  [ "$(<"$session_dir/run/s001/completion_status.txt")" = "complete" ]
  prompt_one="$(<"$session_dir/run/s001/effective_prompt.md")"
  [[ "$prompt_one" == *"output_completion: $session_dir/run/s001/completion_status.txt"* ]]
  [[ "$prompt_one" != *"output_handoff:"* ]]
}

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
  [[ "$output" == *"output_completion=$session_dir/run/s001/completion_status.txt"* ]]
}

@test "dry run preserves a new session-dir path that does not exist yet" {
  session_dir="$TEST_ROOT/nested/session/path"
  expected_session_dir="$session_dir"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 1 \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" != *"cd:"* ]]
  [[ "$output" == *"session_dir=$expected_session_dir"* ]]
  [[ "$output" == *"output_handoff=$expected_session_dir/run/s001/handoff.md"* ]]
}

@test "dry run normalizes relative session-dir dot components" {
  cd "$TEST_ROOT"
  session_dir="./session"
  expected_session_dir="$TEST_ROOT/session"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 1 \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"session_dir=$expected_session_dir"* ]]
  [[ "$output" == *"output_handoff=$expected_session_dir/run/s001/handoff.md"* ]]
}

@test "dry run normalizes relative session-dir parent components" {
  cd "$TEST_ROOT"
  session_dir="./nested/../session"
  expected_session_dir="$TEST_ROOT/session"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 1 \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"session_dir=$expected_session_dir"* ]]
  [[ "$output" == *"output_handoff=$expected_session_dir/run/s001/handoff.md"* ]]
}

@test "dry run normalizes absolute session-dir dot and parent components" {
  session_dir="$TEST_ROOT/./nested/../session"
  expected_session_dir="$TEST_ROOT/session"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 1 \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"session_dir=$expected_session_dir"* ]]
  [[ "$output" == *"output_handoff=$expected_session_dir/run/s001/handoff.md"* ]]
}

@test "agent preset resolves in dry run" {
  run bash "$SCRIPT_PATH" run \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-preset codex \
    --max-steps 1 \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"agent_cmd=codex exec --dangerously-bypass-approvals-and-sandbox -"* ]]
}

@test "agent source defaults to codex preset" {
  run bash "$SCRIPT_PATH" run \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --max-steps 1 \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"agent_cmd=codex exec --dangerously-bypass-approvals-and-sandbox -"* ]]
}

@test "resume rejects run-only options" {
  run bash "$SCRIPT_PATH" resume \
    --session-dir "$TEST_ROOT/session" \
    --prompt-file "$PROMPT_DIR/builder.md"

  [ "$status" -ne 0 ]
  [[ "$output" == *"resume only accepts -s/--session-dir, -n/--additional-steps, --run-to-completion, and -d/--dry-run."* ]]
}

@test "resume rejects --max-steps and points to --additional-steps" {
  run bash "$SCRIPT_PATH" resume \
    --session-dir "$TEST_ROOT/session" \
    --max-steps 2

  [ "$status" -ne 0 ]
  [[ "$output" == *"resume uses --additional-steps (or -n), not --max-steps."* ]]
}

@test "records non-zero agent exit in step artifacts and loop log" {
  session_dir="$TEST_ROOT/session"
  agent_path="$BIN_DIR/agent-fail"
  make_agent "$agent_path" "partial-output\n" "failing-stderr\n" 7

  run bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 1

  [ "$status" -eq 0 ]
  [[ "$output" == *"[step 1] done exit=7"* ]]
  [ "$(<"$session_dir/run/s001/exit_code.txt")" = "7" ]
  [[ "$(<"$session_dir/run/s001/stderr.log")" == *"failing-stderr"* ]]
  [[ "$(<"$session_dir/run/loop/loop.log")" == *"step=1"* ]]
  [[ "$(<"$session_dir/run/loop/loop.log")" == *"exit=7"* ]]
}

@test "writes session artifacts and handoff metadata by default" {
  session_dir="$TEST_ROOT/session"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "agent\n"

  run bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --prompt-file "$PROMPT_DIR/reviewer.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2

  [ "$status" -eq 0 ]
  [ -f "$session_dir/run/s001/effective_prompt.md" ]
  [ -f "$session_dir/run/s001/handoff.md" ]
  [ -f "$session_dir/run/s002/handoff.md" ]
  [ -f "$session_dir/run/loop/loop.log" ]

  step_one_prompt="$(<"$session_dir/run/s001/effective_prompt.md")"
  step_two_prompt="$(<"$session_dir/run/s002/effective_prompt.md")"
  [[ "$step_one_prompt" == *"output_handoff: $session_dir/run/s001/handoff.md"* ]]
  [[ "$step_two_prompt" == *"input_handoff: $session_dir/run/s001/handoff.md"* ]]
  [[ "$step_two_prompt" == *"read input_handoff as advisory context only."* ]]
  [[ "$step_two_prompt" == *"if input_handoff conflicts with or narrows the role prompt, ignore the handoff and follow the role prompt."* ]]
}

@test "supports disabling handoff while keeping session logs" {
  session_dir="$TEST_ROOT/session"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "stdout-only\n" "stderr-only\n"

  run bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --prompt-file "$PROMPT_DIR/reviewer.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2 \
    --no-handoff

  [ "$status" -eq 0 ]
  [ ! -f "$session_dir/run/s001/handoff.md" ]
  [ ! -f "$session_dir/run/s002/handoff.md" ]
  [ -f "$session_dir/run/s001/stdout.log" ]
  [ -f "$session_dir/run/s001/stderr.log" ]
  [ -f "$session_dir/run/s001/exit_code.txt" ]
  [[ "$(<"$session_dir/run/s001/stdout.log")" == *"stdout-only"* ]]
  [[ "$(<"$session_dir/run/s001/stderr.log")" == *"stderr-only"* ]]
  [ "$(<"$session_dir/run/s001/exit_code.txt")" = "0" ]

  prompt_one="$(<"$session_dir/run/s001/effective_prompt.md")"
  [[ "$prompt_one" != *"input_handoff:"* ]]
  [[ "$prompt_one" != *"output_handoff:"* ]]
}

@test "--run-to-completion stops after two consecutive complete judgements" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'complete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_completion_agent "$agent_path" "$sequence_file" "$count_file"

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
  [[ "$(<"$session_dir/run/s001/effective_prompt.md")" == *"output_completion: $session_dir/run/s001/completion_status.txt"* ]]
  [ "$(<"$session_dir/run/s001/completion_status.txt")" = "complete" ]
  [[ "$(<"$session_dir/run/loop/loop.log")" == *"completion_judgement=complete completion_streak=2/2"* ]]
}

@test "incomplete judgement resets the completion streak" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'complete\nincomplete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_completion_agent "$agent_path" "$sequence_file" "$count_file"

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
  make_sequence_completion_agent "$agent_path" "$sequence_file" "$count_file"

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

@test "rotates prompts and agent commands independently across steps" {
  session_dir="$TEST_ROOT/session"
  agent_a="$BIN_DIR/agent-a"
  agent_b="$BIN_DIR/agent-b"
  make_agent "$agent_a" "agent-a\n"
  make_agent "$agent_b" "agent-b\n"

  run bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --prompt-file "$PROMPT_DIR/reviewer.md" \
    --agent-cmd "$agent_a" \
    --agent-cmd "$agent_b" \
    --max-steps 4 \
    --no-handoff

  [ "$status" -eq 0 ]
  [[ "$(<"$session_dir/run/s001/effective_prompt.md")" == *"Builder prompt body."* ]]
  [[ "$(<"$session_dir/run/s002/effective_prompt.md")" == *"Reviewer prompt body."* ]]
  [[ "$(<"$session_dir/run/s003/effective_prompt.md")" == *"Builder prompt body."* ]]
  [[ "$(<"$session_dir/run/s004/effective_prompt.md")" == *"Reviewer prompt body."* ]]
  [[ "$(<"$session_dir/run/s001/stdout.log")" == *"agent-a"* ]]
  [[ "$(<"$session_dir/run/s002/stdout.log")" == *"agent-b"* ]]
  [[ "$(<"$session_dir/run/s003/stdout.log")" == *"agent-a"* ]]
  [[ "$(<"$session_dir/run/s004/stdout.log")" == *"agent-b"* ]]
}

@test "tmux mode works with fake tmux and writes per-step logs" {
  session_dir="$TEST_ROOT/session"
  fake_tmux_root="$TEST_ROOT/fake-tmux"
  mkdir -p "$fake_tmux_root"
  make_fake_tmux

  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "tmux-stdout\n" "tmux-stderr\n"

  run env PATH="$BIN_DIR:$PATH" FAKE_TMUX_ROOT="$fake_tmux_root" bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 1 \
    --tmux \
    --tmux-session-name bats-tmux

  [ "$status" -eq 0 ]
  [[ "$output" == *"tmux_session=bats-tmux"* ]]
  [[ "$output" == *"tmux_attach_cmd=tmux attach -t bats-tmux"* ]]
  [ -f "$session_dir/run/s001/stdout.log" ]
  [ -f "$session_dir/run/s001/stderr.log" ]
  [ -f "$session_dir/run/s001/exit_code.txt" ]
  [[ "$(<"$session_dir/run/s001/stdout.log")" == *"tmux-stdout"* ]]
  [[ "$(<"$session_dir/run/s001/stderr.log")" == *"tmux-stderr"* ]]
  [ "$(<"$session_dir/run/s001/exit_code.txt")" = "0" ]
  [ -f "$fake_tmux_root/sessions/bats-tmux" ]
}

@test "resume continues from last step and treats -n as additional steps" {
  session_dir="$TEST_ROOT/session"
  count_file="$TEST_ROOT/count.txt"
  printf '0\n' > "$count_file"
  agent_path="$BIN_DIR/agent"
  cat > "$agent_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
count="\$(<"$count_file")"
count=\$((count + 1))
printf '%s\n' "\$count" > "$count_file"
printf 'run-%s\n' "\$count"
EOF
  chmod +x "$agent_path"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2 \
    --no-handoff
  [ "$status" -eq 0 ]
  [ -f "$session_dir/run/s002/exit_code.txt" ]
  [ ! -f "$session_dir/run/s003/exit_code.txt" ]

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    -n 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"resume_from_step=3"* ]]
  [ -f "$session_dir/run/s004/exit_code.txt" ]
  [ ! -f "$session_dir/run/s005/exit_code.txt" ]
  [[ "$(<"$session_dir/run/s003/stdout.log")" == *"run-3"* ]]
  [[ "$(<"$session_dir/run/s004/stdout.log")" == *"run-4"* ]]
}

@test "resume accepts legacy sessions without run-to-completion metadata" {
  session_dir="$TEST_ROOT/session"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "legacy-ok"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2 \
    --no-handoff
  [ "$status" -eq 0 ]

  rm "$session_dir/run/meta/run_to_completion.txt"

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    --additional-steps 2 \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=resume"* ]]
  [[ "$output" == *"start_step=3"* ]]
  [[ "$output" == *"max_steps=4"* ]]
  [[ "$output" == *"completion_mode=fixed_steps"* ]]
}

@test "resume treats zero-padded double-digit step directories as decimal" {
  session_dir="$TEST_ROOT/session"
  count_file="$TEST_ROOT/count.txt"
  printf '0\n' > "$count_file"
  agent_path="$BIN_DIR/agent"
  cat > "$agent_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
count="\$(<"$count_file")"
count=\$((count + 1))
printf '%s\n' "\$count" > "$count_file"
printf 'run-%s\n' "\$count"
EOF
  chmod +x "$agent_path"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 10 \
    --no-handoff
  [ "$status" -eq 0 ]
  [ -f "$session_dir/run/s010/exit_code.txt" ]

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    --additional-steps 2 \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"start_step=11"* ]]
  [[ "$output" == *"max_steps=12"* ]]
  [[ "$output" == *"[step 11]"* ]]
  [[ "$output" == *"[step 12]"* ]]
}

@test "resume recomputes a trailing complete streak and stops after the next complete" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'incomplete\ncomplete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_completion_agent "$agent_path" "$sequence_file" "$count_file"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 2 \
    --no-handoff \
    --run-to-completion
  [ "$status" -eq 0 ]
  [ -f "$session_dir/run/s002/exit_code.txt" ]
  [ ! -e "$session_dir/run/s001/handoff.md" ]

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    --additional-steps 3

  [ "$status" -eq 0 ]
  [[ "$output" == *"resume_from_step=3"* ]]
  [[ "$output" == *"Completion confirmed at step 3 after 2 consecutive complete judgements."* ]]
  [ -f "$session_dir/run/s003/exit_code.txt" ]
  [ ! -e "$session_dir/run/s004/exit_code.txt" ]
  [ ! -e "$session_dir/run/s003/handoff.md" ]
}

@test "resume exits immediately when completion was already confirmed" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'complete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_completion_agent "$agent_path" "$sequence_file" "$count_file"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 5 \
    --no-handoff \
    --run-to-completion
  [ "$status" -eq 0 ]
  [ -f "$session_dir/run/s002/exit_code.txt" ]
  [ ! -e "$session_dir/run/s003/exit_code.txt" ]
  [ ! -e "$session_dir/run/s001/handoff.md" ]

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    --additional-steps 5

  [ "$status" -eq 0 ]
  [[ "$output" == *"Completion already confirmed at step 2; no remaining steps to run."* ]]
}

@test "resume --run-to-completion resets the completion streak" {
  session_dir="$TEST_ROOT/session"
  sequence_file="$TEST_ROOT/judgements.txt"
  count_file="$TEST_ROOT/count.txt"
  agent_path="$BIN_DIR/agent"
  printf 'complete\ncomplete\ncomplete\ncomplete\n' > "$sequence_file"
  printf '0\n' > "$count_file"
  make_sequence_completion_agent "$agent_path" "$sequence_file" "$count_file"

  run bash "$SCRIPT_PATH" run \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 5 \
    --no-handoff \
    --run-to-completion
  [ "$status" -eq 0 ]
  [ -f "$session_dir/run/s002/exit_code.txt" ]
  [ ! -e "$session_dir/run/s003/exit_code.txt" ]

  run bash "$SCRIPT_PATH" resume \
    --session-dir "$session_dir" \
    --additional-steps 3 \
    --run-to-completion

  [ "$status" -eq 0 ]
  [[ "$output" == *"resume_from_step=3"* ]]
  [[ "$output" == *"Completion confirmed at step 4 after 2 consecutive complete judgements."* ]]
  [ -f "$session_dir/run/s004/exit_code.txt" ]
  [ ! -e "$session_dir/run/s005/exit_code.txt" ]
}

@test "tmux mode fails clearly when tmux is unavailable" {
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run env PATH="/usr/bin:/bin" /bin/bash "$SCRIPT_PATH" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 1 \
    --tmux

  [ "$status" -ne 0 ]
  [[ "$output" == *"--tmux requires tmux on PATH."* ]]
}

@test "tmux cleanup flag requires tmux mode" {
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run bash "$SCRIPT_PATH" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 1 \
    --tmux-cleanup

  [ "$status" -ne 0 ]
  [[ "$output" == *"--tmux-cleanup requires --tmux."* ]]
}

@test "tmux mode rejects existing session name" {
  session_dir="$TEST_ROOT/session"
  fake_tmux_root="$TEST_ROOT/fake-tmux"
  mkdir -p "$fake_tmux_root/sessions"
  make_fake_tmux
  : > "$fake_tmux_root/sessions/taken-session"
  agent_path="$BIN_DIR/agent"
  make_agent "$agent_path" "ok\n"

  run env PATH="$BIN_DIR:$PATH" FAKE_TMUX_ROOT="$fake_tmux_root" bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$agent_path" \
    --max-steps 1 \
    --tmux \
    --tmux-session-name taken-session

  [ "$status" -ne 0 ]
  [[ "$output" == *"tmux session already exists: taken-session"* ]]
}

@test "ctrl-c in tmux mode force quits and keeps tmux session by default" {
  session_dir="$TEST_ROOT/session"
  fake_tmux_root="$TEST_ROOT/fake-tmux"
  mkdir -p "$fake_tmux_root"
  make_fake_tmux

  slow_agent="$BIN_DIR/slow-agent"
  cat > "$slow_agent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
sleep 2
printf 'done\n'
EOF
  chmod +x "$slow_agent"

  run env PATH="$BIN_DIR:$PATH" FAKE_TMUX_ROOT="$fake_tmux_root" perl -e '
    my $pid = fork();
    die "fork failed" unless defined $pid;
    if ($pid == 0) {
      exec @ARGV or die "exec failed: $!";
    }
    select undef, undef, undef, 0.2;
    kill "INT", $pid;
    waitpid($pid, 0);
    my $st = $?;
    if ($st & 127) {
      exit 128 + ($st & 127);
    }
    exit($st >> 8);
  ' bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$slow_agent" \
    --max-steps 1 \
    --tmux \
    --tmux-session-name interrupt-test

  [ "$status" -ne 0 ]
  [[ "$output" == *"Ctrl-C received; forcing quit now."* ]]
  [ -f "$fake_tmux_root/sessions/interrupt-test" ]
}

@test "tmux cleanup flag removes session on ctrl-c" {
  session_dir="$TEST_ROOT/session"
  fake_tmux_root="$TEST_ROOT/fake-tmux"
  mkdir -p "$fake_tmux_root"
  make_fake_tmux

  slow_agent="$BIN_DIR/slow-agent"
  cat > "$slow_agent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
sleep 2
printf 'done\n'
EOF
  chmod +x "$slow_agent"

  run env PATH="$BIN_DIR:$PATH" FAKE_TMUX_ROOT="$fake_tmux_root" perl -e '
    my $pid = fork();
    die "fork failed" unless defined $pid;
    if ($pid == 0) {
      exec @ARGV or die "exec failed: $!";
    }
    select undef, undef, undef, 0.2;
    kill "INT", $pid;
    waitpid($pid, 0);
    my $st = $?;
    if ($st & 127) {
      exit 128 + ($st & 127);
    }
    exit($st >> 8);
  ' bash "$SCRIPT_PATH" \
    --session-dir "$session_dir" \
    --prompt-file "$PROMPT_DIR/builder.md" \
    --agent-cmd "$slow_agent" \
    --max-steps 1 \
    --tmux \
    --tmux-cleanup \
    --tmux-session-name cleanup-on-interrupt

  [ "$status" -ne 0 ]
  [[ "$output" == *"Ctrl-C received; forcing quit now."* ]]
  [ ! -f "$fake_tmux_root/sessions/cleanup-on-interrupt" ]
}
