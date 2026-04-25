#!/usr/bin/env bash
set -euo pipefail

# File protocol (when session storage is enabled):
# - <session-dir>/run/meta/max_steps.txt
# - <session-dir>/run/meta/handoff_enabled.txt
# - <session-dir>/run/meta/run_to_completion.txt
# - <session-dir>/run/meta/use_tmux.txt
# - <session-dir>/run/meta/tmux_cleanup.txt
# - <session-dir>/run/meta/tmux_session_name.txt
# - <session-dir>/run/meta/prompts.tsv
# - <session-dir>/run/meta/prompts/pNNN-*
# - <session-dir>/run/meta/agent_cmds.txt
# - <session-dir>/run/loop/loop.log
# - <session-dir>/run/sNNN/effective_prompt.md
# - <session-dir>/run/sNNN/stdout.log
# - <session-dir>/run/sNNN/stderr.log
# - <session-dir>/run/sNNN/exit_code.txt
# - <session-dir>/run/sNNN/completion_status.txt (only when run-to-completion is enabled)
# - <session-dir>/run/sNNN/handoff.md (only when handoff is enabled)
# Session storage defaults:
# - enabled with a temp dir
# - overridden with --session-dir
# - disabled with --no-session-dir
# Handoff defaults:
# - enabled when session storage is enabled
# - disabled with --no-session-dir or --no-handoff

usage() {
  cat <<'EOF'
converge.sh - run or resume a rotating agent loop

USAGE
  converge.sh run [options]
  converge.sh resume -s <path> [-n <n>|--additional-steps <n>] [--run-to-completion] [-d]
  converge.sh [options]   # shorthand for run

RUN OPTIONS
  Prompt source:
    -p, --prompt        Inline prompt text. Repeat to rotate prompts.
    -f, --prompt-file   Prompt file path. Repeat to rotate prompts.
  Agent source:
    -a, --agent-cmd     Agent command, repeatable.
    -A, --agent-preset  Agent preset name (codex, claude, cursor-agent), repeatable.
                       Defaults to codex when no agent source is provided.

RUN OPTIONAL
  -s, --session-dir   Session root for run artifacts. Defaults to a new temp dir.
      --no-session-dir
                  Disable session storage and run artifacts.
  -n, --max-steps     Number of loop iterations (default: 10).
      --run-to-completion
                  Stop early after 2 consecutive complete work judgements.
  -t, --tmux          Run each step in a tmux window for live observability.
  -x, --tmux-cleanup  Auto-kill tmux session when loop exits or is interrupted.
  -T, --tmux-session-name
                  Optional tmux session name override.
  -H, --no-handoff    Disable handoff artifacts while keeping the session folder.
  -d, --dry-run       Print resolved execution plan and exit.

RESUME OPTIONS
  -s, --session-dir   Existing session root to resume.
  -n, --additional-steps
                  Additional steps to run from the current end.
      --run-to-completion
                  Enable run-to-completion for resumed steps and reset the streak.
  -d, --dry-run       Print remaining plan and exit.

  -h, --help      Show this help message.

EXAMPLES
  converge.sh run -A codex -p "You are builder" -f ./prompts/inspector.md -n 2
  converge.sh run -a "claude -p --permission-mode bypassPermissions" -s ./session -f ./prompts/judge.md -H
  converge.sh run -A codex -f ./prompts/builder.md --no-session-dir
  converge.sh resume -s ./session --additional-steps 4
EOF
}

agent_preset_command() {
  local preset="$1"
  case "$preset" in
    codex) printf '%s\n' "codex exec --dangerously-bypass-approvals-and-sandbox -" ;;
    claude) printf '%s\n' "claude -p --permission-mode bypassPermissions" ;;
    cursor-agent) printf '%s\n' "cursor-agent -p --yolo --trust --approve-mcps" ;;
    *)
      echo "Unknown --agent-preset: $preset" >&2
      echo "Allowed presets: codex, claude, cursor-agent" >&2
      return 1
      ;;
  esac
}

resolve_file_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
    return
  fi
  printf '%s/%s\n' "$(cd "$(dirname "$path")" && pwd)" "$(basename "$path")"
}

resolve_path_without_creation() {
  local path="$1"
  local IFS="/"
  local -a parts=()
  local -a normalized=()
  local part
  local normalized_count=0
  local idx

  if [[ "$path" != /* ]]; then
    path="$PWD/$path"
  fi

  read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    case "$part" in
      ""|".")
        ;;
      "..")
        if [[ "$normalized_count" -gt 0 ]]; then
          normalized_count=$((normalized_count - 1))
          unset "normalized[$normalized_count]"
        fi
        ;;
      *)
        normalized[$normalized_count]="$part"
        normalized_count=$((normalized_count + 1))
        ;;
    esac
  done

  if [[ "$normalized_count" -eq 0 ]]; then
    printf '/\n'
    return
  fi
  for ((idx = 0; idx < normalized_count; idx++)); do
    printf '/%s' "${normalized[$idx]}"
  done
  printf '\n'
}

build_default_session_dir() {
  local create="$1" tmp_root
  tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  if [[ "$create" -eq 1 ]]; then
    mktemp -d "$tmp_root/converge-session.XXXXXX"
    return
  fi
  tmp_root="$(resolve_path_without_creation "$tmp_root")"
  printf '%s/converge-session.dry-run.%d\n' "$tmp_root" "$$"
}

sanitize_tmux_label() {
  local text="$1" fallback="$2" max_len="$3" safe
  safe="$(printf '%s' "$text" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-*//; s/-*$//')"
  safe="${safe:0:max_len}"
  [[ -n "$safe" ]] || safe="$fallback"
  printf '%s\n' "$safe"
}

build_prompt_snapshot_name() {
  local index="$1" prompt_kind="$2" prompt_value="$3" prompt_label="$4" base_name safe_name
  if [[ -n "$prompt_label" ]]; then
    base_name="$prompt_label"
  elif [[ "$prompt_kind" == "file" ]]; then
    base_name="$(basename "$prompt_value")"
  else
    base_name="inline.md"
  fi
  if [[ "$base_name" == "inline" ]]; then
    base_name="inline.md"
  fi
  safe_name="$(sanitize_tmux_label "$base_name" prompt.md 80)"
  printf 'p%03d-%s\n' "$((index + 1))" "$safe_name"
}

build_tmux_session_name() {
  local provided="$1"
  if [[ -n "$provided" ]]; then
    printf '%s\n' "$provided"
    return
  fi
  printf 'converge-%s-%d\n' "$(date -u +%Y%m%d-%H%M%S)" "$$"
}

build_tmux_window_name() {
  local step="$1" prompt="$2" base stem safe
  base="$(basename "$prompt")"
  stem="${base%.*}"
  safe="$(sanitize_tmux_label "$stem" step 24)"
  printf 's%03d-%s\n' "$step" "$safe"
}

write_prompt_snapshot() {
  local snapshot_path="$1" prompt_kind="$2" prompt_value="$3" tmp_path
  tmp_path="${snapshot_path}.tmp.$$"
  mkdir -p "$(dirname "$snapshot_path")"
  if [[ "$prompt_kind" == "file" ]]; then
    cat "$prompt_value" > "$tmp_path"
  else
    printf '%s\n' "$prompt_value" > "$tmp_path"
  fi
  mv "$tmp_path" "$snapshot_path"
}

snapshot_prompts_into_metadata() {
  local meta_dir="$1" prompts_dir="$meta_dir/prompts"
  local idx prompt_kind prompt_value prompt_label snapshot_name snapshot_path
  local -a stored_prompt_kinds=()
  local -a stored_prompt_values=()
  local -a stored_prompt_labels=()

  mkdir -p "$prompts_dir"
  for idx in "${!prompt_values[@]}"; do
    prompt_kind="${prompt_kinds[$idx]}"
    prompt_value="${prompt_values[$idx]}"
    prompt_label="${prompt_labels[$idx]}"
    snapshot_name="$(build_prompt_snapshot_name "$idx" "$prompt_kind" "$prompt_value" "$prompt_label")"
    snapshot_path="$prompts_dir/$snapshot_name"
    write_prompt_snapshot "$snapshot_path" "$prompt_kind" "$prompt_value"
    stored_prompt_kinds+=("file")
    stored_prompt_values+=("$snapshot_path")
    if [[ -n "$prompt_label" ]]; then
      stored_prompt_labels+=("$prompt_label")
    elif [[ "$prompt_kind" == "file" ]]; then
      stored_prompt_labels+=("$(basename "$prompt_value")")
    else
      stored_prompt_labels+=("inline")
    fi
  done

  prompt_kinds=("${stored_prompt_kinds[@]}")
  prompt_values=("${stored_prompt_values[@]}")
  prompt_labels=("${stored_prompt_labels[@]}")
}

configure_tmux_window() {
  local session_name="$1" window_name="$2" target
  target="${session_name}:${window_name}"
  tmux set-option -t "$target" remain-on-exit on
  tmux set-option -t "$target" automatic-rename off
}

emit_effective_prompt() {
  local step="$1" agent_cmd="$2" input_handoff="$3" output_handoff="$4" output_completion="$5" prompt_kind="$6" prompt_value="$7"
  echo "# Runtime Protocol"
  echo
  echo "- step: $step"
  echo "- agent_cmd: $agent_cmd"
  if [[ "$run_to_completion" -eq 1 ]]; then
    echo "- completion_mode: run_to_completion"
    echo "- completion_streak_target: $completion_streak_target"
    echo "- output_completion: $output_completion"
    echo "- write exactly one word to output_completion: complete|incomplete."
    echo "- use complete only if the entire assignment appears finished and the loop should stop if the next step independently agrees."
    echo "- use incomplete if any implementation, review, verification, or uncertainty remains."
  fi
  if [[ -n "$output_handoff" ]]; then
    if [[ -n "$input_handoff" ]]; then
      echo "- input_handoff: $input_handoff"
      echo "- read input_handoff as advisory context only."
      echo "- the role prompt remains the source of truth for this step."
      echo "- if input_handoff conflicts with or narrows the role prompt, ignore the handoff and follow the role prompt."
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
  echo
  if [[ "$prompt_kind" == "file" ]]; then
    cat "$prompt_value"
  else
    printf '%s\n' "$prompt_value"
  fi
}

run_agent_with_logs() {
  local agent_cmd="$1" effective_prompt="$2" stdout_log="$3" stderr_log="$4"
  local stdout_fifo stderr_fifo tee_stdout_pid tee_stderr_pid code

  stdout_fifo="$(mktemp -u "${TMPDIR:-/tmp}/converge-stdout.XXXXXX")"
  stderr_fifo="$(mktemp -u "${TMPDIR:-/tmp}/converge-stderr.XXXXXX")"
  mkfifo "$stdout_fifo" "$stderr_fifo"
  tee "$stdout_log" < "$stdout_fifo" &
  tee_stdout_pid=$!
  tee "$stderr_log" < "$stderr_fifo" >&2 &
  tee_stderr_pid=$!

  bash -c "$agent_cmd" < "$effective_prompt" > "$stdout_fifo" 2> "$stderr_fifo"
  code=$?

  wait "$tee_stdout_pid"
  wait "$tee_stderr_pid"
  rm -f "$stdout_fifo" "$stderr_fifo"
  return "$code"
}

build_tmux_step_command() {
  local payload="$1" agent_cmd="$2" wait_channel="$3" exit_code_file="$4" stdout_log="${5:-}" stderr_log="${6:-}"
  local escaped_payload escaped_agent_cmd command escaped_stdout escaped_stderr escaped_wait_channel escaped_exit_code_file
  escaped_payload="$(printf '%q' "$payload")"
  escaped_agent_cmd="$(printf '%q' "$agent_cmd")"
  escaped_wait_channel="$(printf '%q' "$wait_channel")"
  escaped_exit_code_file="$(printf '%q' "$exit_code_file")"
  command="printf '%s' $escaped_payload | bash -c $escaped_agent_cmd"
  if [[ -n "$stdout_log" && -n "$stderr_log" ]]; then
    escaped_stdout="$(printf '%q' "$stdout_log")"
    escaped_stderr="$(printf '%q' "$stderr_log")"
    printf "set -o pipefail; stdout_fifo=\$(mktemp -u); stderr_fifo=\$(mktemp -u); mkfifo \"\$stdout_fifo\" \"\$stderr_fifo\"; tee %s < \"\$stdout_fifo\" & tee_stdout_pid=\$!; tee %s < \"\$stderr_fifo\" >&2 & tee_stderr_pid=\$!; %s > \"\$stdout_fifo\" 2> \"\$stderr_fifo\"; code=\$?; wait \"\$tee_stdout_pid\" \"\$tee_stderr_pid\"; rm -f \"\$stdout_fifo\" \"\$stderr_fifo\"; printf '%%s\\n' \"\$code\" > %s; tmux wait-for -S %s; exit \"\$code\"\n" \
      "$escaped_stdout" "$escaped_stderr" "$command" "$escaped_exit_code_file" "$escaped_wait_channel"
    return
  fi
  printf "set -o pipefail; %s; code=\$?; printf '%%s\\n' \"\$code\" > %s; tmux wait-for -S %s; exit \"\$code\"\n" \
    "$command" "$escaped_exit_code_file" "$escaped_wait_channel"
}

build_tmux_wait_channel() {
  local session_name="$1" window_name="$2" step="$3" safe_session safe_window
  safe_session="$(sanitize_tmux_label "$session_name" session 32)"
  safe_window="$(sanitize_tmux_label "$window_name" window 32)"
  printf 'converge.%s.%s.%03d.%d\n' "$safe_session" "$safe_window" "$step" "$$"
}

wait_for_tmux_window() {
  local wait_channel="$1" exit_code_file="$2" code=""
  tmux_wait_code=""
  active_tmux_wait_pid=""
  tmux wait-for "$wait_channel" &
  active_tmux_wait_pid=$!

  set +e
  wait "$active_tmux_wait_pid"
  tmux_wait_status=$?
  set -e
  active_tmux_wait_pid=""
  if [[ "$tmux_wait_status" -ne 0 ]]; then
    return 1
  fi
  if [[ -f "$exit_code_file" ]]; then
    code="$(<"$exit_code_file")"
  fi
  if [[ "$code" =~ ^[0-9]+$ ]]; then
    tmux_wait_code="$code"
    return 0
  fi
  return 1
}

cleanup_active_tmux_files() {
  if [[ -n "$active_tmux_exit_code_file" ]]; then
    rm -f "$active_tmux_exit_code_file"
    active_tmux_exit_code_file=""
  fi
}

cleanup_on_interrupt() {
  set +e
  if [[ -n "${active_tmux_wait_pid:-}" ]]; then
    kill "$active_tmux_wait_pid" >/dev/null 2>&1 || true
    active_tmux_wait_pid=""
  fi
  cleanup_active_tmux_files
  if [[ "$use_tmux" -eq 1 && "$tmux_cleanup" -eq 1 && -n "$tmux_session_name" ]]; then
    tmux has-session -t "$tmux_session_name" >/dev/null 2>&1 && tmux kill-session -t "$tmux_session_name" >/dev/null 2>&1
  fi
  exit "${1:-130}"
}

handle_sigint() {
  echo "Ctrl-C received; forcing quit now." >&2
  trap - INT TERM
  cleanup_on_interrupt 130
}

handle_sigterm() {
  echo "Termination signal received; cleaning up." >&2
  cleanup_on_interrupt 143
}

write_run_metadata() {
  local meta_dir="$1"
  local idx prompt_label
  mkdir -p "$meta_dir"
  snapshot_prompts_into_metadata "$meta_dir"
  printf '%s\n' "$max_steps" > "$meta_dir/max_steps.txt"
  printf '%s\n' "$handoff_enabled" > "$meta_dir/handoff_enabled.txt"
  printf '%s\n' "$run_to_completion" > "$meta_dir/run_to_completion.txt"
  printf '%s\n' "$use_tmux" > "$meta_dir/use_tmux.txt"
  printf '%s\n' "$tmux_cleanup" > "$meta_dir/tmux_cleanup.txt"
  printf '%s\n' "$tmux_session_name_requested" > "$meta_dir/tmux_session_name.txt"
  : > "$meta_dir/prompts.tsv"
  : > "$meta_dir/agent_cmds.txt"
  for idx in "${!prompt_values[@]}"; do
    prompt_label="${prompt_labels[$idx]}"
    printf '%s\t%s\t%s\n' "${prompt_kinds[$idx]}" "${prompt_values[$idx]}" "$prompt_label" >> "$meta_dir/prompts.tsv"
  done
  printf '%s\n' "${agent_cmds[@]}" > "$meta_dir/agent_cmds.txt"
}

load_run_metadata() {
  local meta_dir="$1"
  local prompts_file="$meta_dir/prompts.tsv"
  local cmds_file="$meta_dir/agent_cmds.txt"
  [[ -f "$meta_dir/max_steps.txt" ]] || { echo "Cannot resume: missing $meta_dir/max_steps.txt" >&2; exit 1; }
  [[ -f "$meta_dir/handoff_enabled.txt" ]] || { echo "Cannot resume: missing $meta_dir/handoff_enabled.txt" >&2; exit 1; }
  [[ -f "$meta_dir/use_tmux.txt" ]] || { echo "Cannot resume: missing $meta_dir/use_tmux.txt" >&2; exit 1; }
  [[ -f "$meta_dir/tmux_session_name.txt" ]] || { echo "Cannot resume: missing $meta_dir/tmux_session_name.txt" >&2; exit 1; }
  [[ -f "$prompts_file" ]] || { echo "Cannot resume: missing $prompts_file" >&2; exit 1; }
  [[ -f "$cmds_file" ]] || { echo "Cannot resume: missing $cmds_file" >&2; exit 1; }

  stored_max_steps="$(<"$meta_dir/max_steps.txt")"
  handoff_enabled="$(<"$meta_dir/handoff_enabled.txt")"
  if [[ -f "$meta_dir/run_to_completion.txt" ]]; then
    run_to_completion="$(<"$meta_dir/run_to_completion.txt")"
  else
    run_to_completion=0
  fi
  use_tmux="$(<"$meta_dir/use_tmux.txt")"
  if [[ -f "$meta_dir/tmux_cleanup.txt" ]]; then
    tmux_cleanup="$(<"$meta_dir/tmux_cleanup.txt")"
  else
    tmux_cleanup=0
  fi
  tmux_session_name_requested="$(<"$meta_dir/tmux_session_name.txt")"
  [[ "$stored_max_steps" =~ ^[0-9]+$ && "$stored_max_steps" -gt 0 ]] || { echo "Invalid stored max steps: $stored_max_steps" >&2; exit 1; }
  [[ "$handoff_enabled" =~ ^[01]$ ]] || { echo "Invalid stored handoff flag: $handoff_enabled" >&2; exit 1; }
  [[ "$run_to_completion" =~ ^[01]$ ]] || { echo "Invalid stored run-to-completion flag: $run_to_completion" >&2; exit 1; }
  [[ "$use_tmux" =~ ^[01]$ ]] || { echo "Invalid stored tmux flag: $use_tmux" >&2; exit 1; }
  [[ "$tmux_cleanup" =~ ^[01]$ ]] || { echo "Invalid stored tmux cleanup flag: $tmux_cleanup" >&2; exit 1; }

  prompt_kinds=()
  prompt_values=()
  prompt_labels=()
  while IFS=$'\t' read -r prompt_kind prompt_value prompt_label || [[ -n "$prompt_kind$prompt_value$prompt_label" ]]; do
    [[ -n "$prompt_kind" ]] || continue
    prompt_kinds+=("$prompt_kind")
    prompt_values+=("$prompt_value")
    if [[ -n "$prompt_label" ]]; then
      prompt_labels+=("$prompt_label")
    elif [[ "$prompt_kind" == "file" ]]; then
      prompt_labels+=("$(basename "$prompt_value")")
    else
      prompt_labels+=("inline")
    fi
  done < "$prompts_file"

  agent_cmds=()
  while IFS= read -r cmd || [[ -n "$cmd" ]]; do
    [[ -n "$cmd" ]] || continue
    agent_cmds+=("$cmd")
  done < "$cmds_file"
}

require_positive_integer() {
  local value="$1" flag="$2"
  [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]] || {
    echo "$flag must be a positive integer." >&2
    exit 1
  }
}

validate_cli_prompts() {
  local idx prompt_kind prompt_value
  for idx in "${!cli_prompt_values[@]}"; do
    prompt_kind="${cli_prompt_kinds[$idx]}"
    prompt_value="${cli_prompt_values[$idx]}"
    [[ -n "$prompt_value" ]] || {
      if [[ "$prompt_kind" == "inline" ]]; then
        echo "--prompt requires a non-empty value." >&2
      else
        echo "--prompt-file requires a non-empty value." >&2
      fi
      exit 1
    }
    if [[ "$prompt_kind" == "file" ]]; then
      [[ -f "$prompt_value" ]] || { echo "Prompt file not found: $prompt_value" >&2; exit 1; }
    fi
  done
}

build_prompts_from_cli() {
  local idx prompt_kind prompt_value path
  prompt_kinds=()
  prompt_values=()
  prompt_labels=()
  for idx in "${!cli_prompt_values[@]}"; do
    prompt_kind="${cli_prompt_kinds[$idx]}"
    prompt_value="${cli_prompt_values[$idx]}"
    if [[ "$prompt_kind" == "file" ]]; then
      path="$(resolve_file_path "$prompt_value")"
      prompt_kinds+=("file")
      prompt_values+=("$path")
      prompt_labels+=("$(basename "$path")")
    else
      prompt_kinds+=("inline")
      prompt_values+=("$prompt_value")
      prompt_labels+=("inline")
    fi
  done
}

ensure_prompt_files_exist() {
  local idx prompt_kind prompt_value
  for idx in "${!prompt_values[@]}"; do
    prompt_kind="${prompt_kinds[$idx]}"
    prompt_value="${prompt_values[$idx]}"
    if [[ "$prompt_kind" == "file" ]]; then
      [[ -f "$prompt_value" ]] || { echo "Prompt file not found: $prompt_value" >&2; exit 1; }
    fi
  done
}

find_last_completed_step() {
  local root="$1" step_dir stem num last=0
  for step_dir in "$root"/s[0-9][0-9][0-9]; do
    [[ -d "$step_dir" ]] || continue
    [[ -f "$step_dir/exit_code.txt" ]] || continue
    stem="$(basename "$step_dir")"
    num="${stem#s}"
    [[ "$num" =~ ^[0-9]+$ ]] || continue
    num="$((10#$num))"
    (( num > last )) && last="$num"
  done
  printf '%s\n' "$last"
}

resolve_step_context() {
  local step="$1" prompt_index
  prompt_index="$(( (step - 1) % ${#prompt_values[@]} ))"
  step_prompt_kind="${prompt_kinds[$prompt_index]}"
  step_prompt_value="${prompt_values[$prompt_index]}"
  step_prompt_label="${prompt_labels[$prompt_index]}"
  step_agent_cmd="${agent_cmds[$(( (step - 1) % ${#agent_cmds[@]} ))]}"
}

compute_handoff_paths() {
  local step="$1"
  step_input_handoff=""
  step_output_handoff=""
  if [[ -n "$session_dir" && "$handoff_enabled" -eq 1 ]]; then
    if [[ "$step" -gt 1 ]]; then
      step_input_handoff="$(printf '%s/s%03d/handoff.md' "$run_dir" "$((step - 1))")"
    fi
    step_output_handoff="$(printf '%s/s%03d/handoff.md' "$run_dir" "$step")"
  fi
}

compute_completion_path() {
  local step="$1"
  step_output_completion=""
  if [[ -n "$session_dir" && "$run_to_completion" -eq 1 ]]; then
    step_output_completion="$(printf '%s/s%03d/completion_status.txt' "$run_dir" "$step")"
  fi
}

parse_completion_judgement() {
  local completion_path="$1" judgement=""
  parsed_completion_judgement=""
  [[ -f "$completion_path" ]] || return 0
  judgement="$(tr -d '\r' < "$completion_path")"
  judgement="$(printf '%s' "$judgement" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  case "$judgement" in
    complete|incomplete) parsed_completion_judgement="$judgement" ;;
    *) parsed_completion_judgement="" ;;
  esac
}

recompute_completion_streak() {
  local root="$1" last_step="$2" step completion_path
  completion_streak=0
  for ((step=last_step; step>=1; step--)); do
    completion_path="$(printf '%s/s%03d/completion_status.txt' "$root" "$step")"
    parse_completion_judgement "$completion_path"
    if [[ "$parsed_completion_judgement" == "complete" ]]; then
      completion_streak=$((completion_streak + 1))
    else
      break
    fi
  done
}

record_step_completion_state() {
  local completion_path="$1"
  parse_completion_judgement "$completion_path"
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

print_plan() {
  local start_step="$1" end_step="$2"
  local step input_handoff output_handoff output_completion
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
  for ((step=start_step; step<=end_step; step++)); do
    resolve_step_context "$step"
    compute_handoff_paths "$step"
    compute_completion_path "$step"
    input_handoff="$step_input_handoff"
    output_handoff="$step_output_handoff"
    output_completion="$step_output_completion"
    echo "[step $step] prompt=$step_prompt_label kind=$step_prompt_kind"
    if [[ "$step_prompt_kind" == "file" ]]; then
      echo "  prompt_file=$step_prompt_value"
    fi
    echo "  agent_cmd=$step_agent_cmd"
    if [[ -n "$output_completion" ]]; then
      echo "  output_completion=$output_completion"
    fi
    if [[ -n "$input_handoff" ]]; then
      echo "  input_handoff=$input_handoff"
    fi
    if [[ -n "$output_handoff" ]]; then
      echo "  output_handoff=$output_handoff"
    fi
  done
  return 0
}

mode="run"
if [[ $# -gt 0 ]]; then
  case "$1" in
    run|resume)
      mode="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      mode="run"
      ;;
    *)
      echo "Unknown subcommand: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
fi

session_dir="" max_steps=10 use_tmux=0 tmux_cleanup=0 tmux_session_name="" tmux_session_name_requested="" tmux_created=0 handoff_disabled=0
session_dir_mode="auto"
run_to_completion=0 completion_streak_target=2 completion_streak=0
active_tmux_exit_code_file=""
active_tmux_wait_pid=""
tmux_wait_code=""
current_completion_judgement=""
parsed_completion_judgement=""
completed_steps=0
dry_run=0
cli_prompt_kinds=()
cli_prompt_values=()
agent_cmds=()
resume_additional_steps=""
resume_reset_completion_streak=0

trap 'handle_sigint' INT
trap 'handle_sigterm' TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--session-dir)
      session_dir="${2:-}"
      session_dir_mode="custom"
      shift 2
      ;;
    --no-session-dir)
      session_dir=""
      session_dir_mode="disabled"
      shift
      ;;
    -n)
      if [[ "$mode" == "resume" ]]; then
        resume_additional_steps="${2:-}"
      else
        max_steps="${2:-}"
      fi
      shift 2
      ;;
    --max-steps)
      if [[ "$mode" == "resume" ]]; then
        echo "resume uses --additional-steps (or -n), not --max-steps." >&2
        exit 1
      fi
      max_steps="${2:-}"
      shift 2
      ;;
    --additional-steps)
      if [[ "$mode" != "resume" ]]; then
        echo "--additional-steps is resume-only; use --max-steps for run." >&2
        exit 1
      fi
      resume_additional_steps="${2:-}"
      shift 2
      ;;
    --run-to-completion)
      run_to_completion=1
      if [[ "$mode" == "resume" ]]; then
        resume_reset_completion_streak=1
      fi
      shift
      ;;
    -d|--dry-run) dry_run=1; shift ;;
    -p|--prompt|-f|--prompt-file|-a|--agent-cmd|-A|--agent-preset|-t|--tmux|-x|--tmux-cleanup|-T|--tmux-session-name|-H|--no-handoff)
      if [[ "$mode" == "resume" ]]; then
        echo "resume only accepts -s/--session-dir, -n/--additional-steps, --run-to-completion, and -d/--dry-run." >&2
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
        -t|--tmux) use_tmux=1; shift ;;
        -x|--tmux-cleanup) tmux_cleanup=1; shift ;;
        -T|--tmux-session-name) tmux_session_name_requested="${2:-}"; shift 2 ;;
        -H|--no-handoff) handoff_disabled=1; shift ;;
      esac
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

prompt_kinds=()
prompt_values=()
prompt_labels=()
stored_max_steps=""
last_completed_step=0
start_step=1
if [[ "$mode" == "run" ]]; then
  if [[ ${#cli_prompt_values[@]} -eq 0 ]]; then
    echo "Provide at least one --prompt or --prompt-file." >&2
    usage >&2
    exit 1
  fi
  if [[ ${#agent_cmds[@]} -eq 0 ]]; then
    agent_cmds+=("$(agent_preset_command codex)")
  fi
  require_positive_integer "$max_steps" "--max-steps"
  for agent_cmd in "${agent_cmds[@]}"; do
    [[ -n "$agent_cmd" ]] || { echo "--agent-cmd requires a non-empty value." >&2; exit 1; }
  done
  validate_cli_prompts
  if [[ "$session_dir_mode" == "custom" ]]; then
    [[ -n "$session_dir" ]] || { echo "--session-dir requires a non-empty value." >&2; exit 1; }
  fi
  if [[ "$session_dir_mode" == "auto" ]]; then
    if [[ "$dry_run" -eq 1 ]]; then
      session_dir="$(build_default_session_dir 0)"
    else
      session_dir="$(build_default_session_dir 1)"
      session_dir="$(cd "$session_dir" && pwd)"
    fi
  fi
  if [[ "$session_dir_mode" != "disabled" && "$handoff_disabled" -eq 0 ]]; then
    handoff_enabled=1
  else
    handoff_enabled=0
  fi
  if [[ "$session_dir_mode" == "custom" ]]; then
    if [[ "$dry_run" -eq 1 ]]; then
      session_dir="$(resolve_path_without_creation "$session_dir")"
    else
      session_dir="$(mkdir -p "$session_dir" && cd "$session_dir" && pwd)"
    fi
  fi
  build_prompts_from_cli
  [[ ${#prompt_values[@]} -gt 0 ]] || { echo "No prompts were provided." >&2; exit 1; }
else
  [[ -n "$session_dir" ]] || { echo "resume requires --session-dir." >&2; exit 1; }
  session_dir="$(cd "$session_dir" && pwd)"
  run_dir="$session_dir/run"
  meta_dir="$run_dir/meta"
  [[ -d "$run_dir" ]] || { echo "Cannot resume: run directory not found: $run_dir" >&2; exit 1; }
  load_run_metadata "$meta_dir"
  last_completed_step="$(find_last_completed_step "$run_dir")"

  if [[ "$resume_reset_completion_streak" -eq 1 ]]; then
    run_to_completion=1
  fi
  if [[ -n "$resume_additional_steps" ]]; then
    require_positive_integer "$resume_additional_steps" "--additional-steps"
    max_steps=$((last_completed_step + resume_additional_steps))
  else
    max_steps="$stored_max_steps"
  fi
  if (( max_steps < last_completed_step )); then
    echo "Resolved max steps must be >= last completed step ($last_completed_step)." >&2
    exit 1
  fi
  start_step=$((last_completed_step + 1))
  ensure_prompt_files_exist
  [[ ${#prompt_values[@]} -gt 0 ]] || { echo "Cannot resume: no stored prompts found." >&2; exit 1; }
  [[ ${#agent_cmds[@]} -gt 0 ]] || { echo "Cannot resume: no stored agent commands found." >&2; exit 1; }
fi

if [[ "$run_to_completion" -eq 1 && -z "$session_dir" ]]; then
  echo "--run-to-completion requires session storage; remove --no-session-dir." >&2
  exit 1
fi
run_dir=""
loop_log=""
if [[ -n "$session_dir" ]]; then
  run_dir="$session_dir/run"
  loop_log="$run_dir/loop/loop.log"
  if [[ "$dry_run" -eq 0 ]]; then
    mkdir -p "$run_dir/loop"
    touch "$loop_log"
  fi
fi

if [[ "$use_tmux" -eq 1 ]]; then
  command -v tmux >/dev/null 2>&1 || { echo "--tmux requires tmux on PATH." >&2; exit 1; }
  tmux_session_name="$(build_tmux_session_name "$tmux_session_name_requested")"
  if [[ "$dry_run" -eq 0 ]]; then
    if tmux has-session -t "$tmux_session_name" >/dev/null 2>&1; then
      echo "tmux session already exists: $tmux_session_name" >&2
      exit 1
    fi
  fi
fi

if [[ "$tmux_cleanup" -eq 1 && "$use_tmux" -eq 0 ]]; then
  echo "--tmux-cleanup requires --tmux." >&2
  exit 1
fi

if [[ "$dry_run" -eq 1 ]]; then
  print_plan "$start_step" "$max_steps"
  if (( start_step > max_steps )); then
    echo "No remaining steps to run."
  fi
  exit 0
fi

if [[ -n "$session_dir" ]]; then
  write_run_metadata "$run_dir/meta"
fi

echo "Starting agent loop (mode=$mode)"
if [[ -n "$session_dir" ]]; then
  echo "session_dir=$session_dir"
fi
echo "prompt_count=${#prompt_values[@]}"
echo "max_steps=$max_steps"
if [[ "$run_to_completion" -eq 1 ]]; then
  echo "completion_mode=run_to_completion"
  echo "completion_streak_target=$completion_streak_target"
else
  echo "completion_mode=fixed_steps"
fi
if [[ "$mode" == "resume" ]]; then
  echo "resume_from_step=$start_step"
fi
if [[ ${#agent_cmds[@]} -eq 1 ]]; then
  echo "agent_cmd=${agent_cmds[0]}"
else
  echo "agent_cmd_count=${#agent_cmds[@]}"
fi
if [[ "$use_tmux" -eq 1 ]]; then
  printf -v tmux_attach_target '%q' "$tmux_session_name"
  echo "tmux_session=$tmux_session_name"
  echo "tmux_attach_cmd=tmux attach -t $tmux_attach_target"
fi

if [[ "$mode" == "resume" && "$run_to_completion" -eq 1 ]]; then
  if [[ "$resume_reset_completion_streak" -eq 1 ]]; then
    completion_streak=0
  else
    recompute_completion_streak "$run_dir" "$last_completed_step"
    if (( completion_streak >= completion_streak_target )); then
      echo "Completion already confirmed at step $last_completed_step; no remaining steps to run."
      exit 0
    fi
  fi
fi

if (( start_step > max_steps )); then
  echo "No remaining steps to run."
fi

for ((step=start_step; step<=max_steps; step++)); do
  resolve_step_context "$step"
  prompt_kind="$step_prompt_kind"
  prompt_value="$step_prompt_value"
  prompt_label="$step_prompt_label"
  agent_cmd="$step_agent_cmd"
  compute_handoff_paths "$step"
  compute_completion_path "$step"
  input_handoff="$step_input_handoff"
  output_handoff="$step_output_handoff"
  output_completion="$step_output_completion"
  step_dir=""
  stdout_log=""
  stderr_log=""

  start_epoch="$(date +%s)"
  start_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "[step $step] start prompt=$prompt_label time=$start_iso"

  if [[ -n "$session_dir" ]]; then
    step_dir="$(printf '%s/s%03d' "$run_dir" "$step")"
    mkdir -p "$step_dir"
    effective="$step_dir/effective_prompt.md"
    stdout_log="$step_dir/stdout.log"
    stderr_log="$step_dir/stderr.log"
    : > "$stdout_log"; : > "$stderr_log"
    if [[ "$handoff_enabled" -eq 1 ]]; then
      if [[ -n "$input_handoff" && ! -f "$input_handoff" ]]; then
        input_handoff=""
      fi
      : > "$output_handoff"
    fi
    if [[ -n "$output_completion" ]]; then
      : > "$output_completion"
    fi
    emit_effective_prompt "$step" "$agent_cmd" "$input_handoff" "$output_handoff" "$output_completion" "$prompt_kind" "$prompt_value" > "$effective"
    if [[ "$use_tmux" -eq 0 ]]; then
      set +e
      run_agent_with_logs "$agent_cmd" "$effective" "$stdout_log" "$stderr_log"
      code=$?
      set -e
      printf '%s\n' "$code" > "$step_dir/exit_code.txt"
    fi
  fi

  if [[ "$use_tmux" -eq 1 ]]; then
    if [[ -n "$output_completion" ]]; then
      : > "$output_completion"
    fi
    effective_prompt="$(emit_effective_prompt "$step" "$agent_cmd" "$input_handoff" "$output_handoff" "$output_completion" "$prompt_kind" "$prompt_value")"
    window_name="$(build_tmux_window_name "$step" "$prompt_label")"
    wait_channel="$(build_tmux_wait_channel "$tmux_session_name" "$window_name" "$step")"
    active_tmux_exit_code_file="$(mktemp "${TMPDIR:-/tmp}/converge-tmux-exit.XXXXXX")"
    tmux_cmd="$(build_tmux_step_command "$effective_prompt" "$agent_cmd" "$wait_channel" "$active_tmux_exit_code_file" "$stdout_log" "$stderr_log")"
    if [[ "$tmux_created" -eq 0 ]]; then
      tmux new-session -d -s "$tmux_session_name" -n "$window_name" bash -c "$tmux_cmd"
      configure_tmux_window "$tmux_session_name" "$window_name"
      tmux_created=1
    else
      tmux new-window -d -t "$tmux_session_name" -n "$window_name" bash -c "$tmux_cmd"
      configure_tmux_window "$tmux_session_name" "$window_name"
    fi
    if wait_for_tmux_window "$wait_channel" "$active_tmux_exit_code_file"; then
      code="$tmux_wait_code"
    else
      code=1
    fi
    cleanup_active_tmux_files
    if [[ -n "$step_dir" ]]; then
      printf '%s\n' "$code" > "$step_dir/exit_code.txt"
    fi
  elif [[ -z "$session_dir" ]]; then
    set +e
    emit_effective_prompt "$step" "$agent_cmd" "$input_handoff" "$output_handoff" "$output_completion" "$prompt_kind" "$prompt_value" | bash -c "$agent_cmd"
    code=$?
    set -e
  fi

  end_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  elapsed=$(( $(date +%s) - start_epoch ))
  echo "[step $step] done exit=$code elapsed=${elapsed}s"
  completed_steps=$((completed_steps + 1))
  if [[ "$run_to_completion" -eq 1 ]]; then
    record_step_completion_state "$output_completion"
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

if [[ "$use_tmux" -eq 1 && "$tmux_cleanup" -eq 1 && -n "$tmux_session_name" ]]; then
  tmux has-session -t "$tmux_session_name" >/dev/null 2>&1 && tmux kill-session -t "$tmux_session_name" >/dev/null 2>&1
fi

echo "Loop finished after $completed_steps executed steps."
