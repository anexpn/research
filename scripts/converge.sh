#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
converge.sh - run rotating agent loop with optional session artifacts and handoff

USAGE
  converge.sh [--session-dir <path>] --prompt-list <path> --agent-cmd "<command>" [--agent-cmd "<command>" ...] [--max-steps <n>] [--tmux] [--tmux-session-name <name>] [--handoff | --no-handoff]

REQUIRED
  --prompt-list   File with one prompt path per line (rotation order).
  --agent-cmd     Agent command, e.g. "codex exec" or "claude". Repeat to rotate commands per step.

OPTIONAL
  --session-dir   Session root for run artifacts.
  --max-steps     Number of loop iterations (default: 10).
  --tmux          Run each step in a tmux window for live observability.
  --tmux-session-name
                  Optional tmux session name override.
  --handoff       Force handoff artifacts on. Requires --session-dir.
  --no-handoff    Disable handoff artifacts.
  -h, --help      Show this help message.

PROMPT LIST RULES
  - Empty lines are ignored.
  - Lines starting with # are ignored.
  - Relative prompt paths are resolved from the prompt-list directory.

EXAMPLES
  converge.sh --prompt-list ./prompts.txt --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" --max-steps 2
  converge.sh --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "claude -p --permission-mode bypassPermissions" --no-handoff
  converge.sh --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "cursor-agent -p --yolo --trust --approve-mcps" --handoff
EOF
}

sanitize_tmux_label() {
  local text="$1" fallback="$2" max_len="$3" safe
  safe="$(printf '%s' "$text" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-*//; s/-*$//')"
  safe="${safe:0:max_len}"
  [[ -n "$safe" ]] || safe="$fallback"
  printf '%s\n' "$safe"
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

configure_tmux_window() {
  local session_name="$1" window_name="$2" target
  target="${session_name}:${window_name}"
  tmux set-option -t "$target" remain-on-exit on
  tmux set-option -t "$target" automatic-rename off
}

emit_effective_prompt() {
  local step="$1" agent_cmd="$2" input_handoff="$3" output_handoff="$4" prompt="$5"
  echo "# Runtime Protocol"
  echo
  echo "- step: $step"
  echo "- agent_cmd: $agent_cmd"
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
  echo
  cat "$prompt"
}

build_tmux_step_command() {
  local payload="$1" agent_cmd="$2" stdout_log="${3:-}" stderr_log="${4:-}"
  local escaped_payload escaped_agent_cmd command escaped_stdout escaped_stderr
  escaped_payload="$(printf '%q' "$payload")"
  escaped_agent_cmd="$(printf '%q' "$agent_cmd")"
  command="printf '%s' $escaped_payload | bash -c $escaped_agent_cmd"
  if [[ -n "$stdout_log" && -n "$stderr_log" ]]; then
    escaped_stdout="$(printf '%q' "$stdout_log")"
    escaped_stderr="$(printf '%q' "$stderr_log")"
    command="$command > >(tee $escaped_stdout) 2> >(tee $escaped_stderr >&2)"
  fi
  printf 'set -o pipefail; %s\n' "$command"
}

wait_for_tmux_window() {
  local session_name="$1" window_name="$2" target dead code
  target="${session_name}:${window_name}"
  while true; do
    dead="$(tmux list-panes -t "$target" -F '#{pane_dead}' 2>/dev/null || true)"
    [[ "$dead" == "1" ]] && break
    sleep 0.1
  done
  code="$(tmux display-message -p -t "$target" '#{pane_dead_status}')"
  printf '%s\n' "${code:-1}"
}

session_dir="" prompt_list="" max_steps=10 use_tmux=0 tmux_session_name="" tmux_created=0 handoff_mode="auto"
agent_cmds=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-dir) session_dir="${2:-}"; shift 2 ;;
    --prompt-list) prompt_list="${2:-}"; shift 2 ;;
    --agent-cmd) agent_cmds+=("${2:-}"); shift 2 ;;
    --max-steps) max_steps="${2:-}"; shift 2 ;;
    --tmux) use_tmux=1; shift ;;
    --tmux-session-name) tmux_session_name="${2:-}"; shift 2 ;;
    --handoff) handoff_mode="on"; shift ;;
    --no-handoff) handoff_mode="off"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$prompt_list" && ${#agent_cmds[@]} -gt 0 ]] || { usage >&2; exit 1; }
[[ -f "$prompt_list" ]] || { echo "Prompt list not found: $prompt_list" >&2; exit 1; }
[[ "$max_steps" =~ ^[0-9]+$ && "$max_steps" -gt 0 ]] || { echo "--max-steps must be a positive integer." >&2; exit 1; }
for agent_cmd in "${agent_cmds[@]}"; do
  [[ -n "$agent_cmd" ]] || { echo "--agent-cmd requires a non-empty value." >&2; exit 1; }
done
[[ "$handoff_mode" != "on" || -n "$session_dir" ]] || { echo "--handoff requires --session-dir." >&2; exit 1; }
if [[ "$handoff_mode" == "auto" ]]; then
  if [[ -n "$session_dir" ]]; then
    handoff_enabled=1
  else
    handoff_enabled=0
  fi
elif [[ "$handoff_mode" == "on" ]]; then
  handoff_enabled=1
else
  handoff_enabled=0
fi

if [[ -n "$session_dir" ]]; then
  session_dir="$(mkdir -p "$session_dir" && cd "$session_dir" && pwd)"
fi
prompt_list="$(cd "$(dirname "$prompt_list")" && pwd)/$(basename "$prompt_list")"
prompt_list_dir="$(cd "$(dirname "$prompt_list")" && pwd)"

prompts=()
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="$(printf '%s' "$raw" | sed 's/[[:space:]]*$//')"
  [[ -z "$line" || "$line" == \#* ]] && continue
  path="$line"; [[ "$path" = /* ]] || path="$prompt_list_dir/$path"
  [[ -f "$path" ]] || { echo "Prompt file not found: $path" >&2; exit 1; }
  prompts+=("$path")
done < "$prompt_list"
[[ ${#prompts[@]} -gt 0 ]] || { echo "Prompt list contains no usable prompt files." >&2; exit 1; }

run_dir=""
loop_log=""
if [[ -n "$session_dir" ]]; then
  run_dir="$session_dir/run"
  loop_log="$run_dir/loop/loop.log"
  mkdir -p "$run_dir/loop"
  touch "$loop_log"
fi

if [[ "$use_tmux" -eq 1 ]]; then
  command -v tmux >/dev/null 2>&1 || { echo "--tmux requires tmux on PATH." >&2; exit 1; }
  tmux_session_name="$(build_tmux_session_name "$tmux_session_name")"
  if tmux has-session -t "$tmux_session_name" >/dev/null 2>&1; then
    echo "tmux session already exists: $tmux_session_name" >&2
    exit 1
  fi
fi

echo "Starting agent loop"
if [[ -n "$session_dir" ]]; then
  echo "session_dir=$session_dir"
fi
echo "prompt_count=${#prompts[@]}"
echo "max_steps=$max_steps"
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

for ((step=1; step<=max_steps; step++)); do
  prompt="${prompts[$(( (step - 1) % ${#prompts[@]} ))]}"
  agent_cmd="${agent_cmds[$(( (step - 1) % ${#agent_cmds[@]} ))]}"
  input_handoff=""
  output_handoff=""
  step_dir=""
  stdout_log=""
  stderr_log=""

  start_epoch="$(date +%s)"
  start_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "[step $step] start prompt=$(basename "$prompt") time=$start_iso"

  if [[ -n "$session_dir" ]]; then
    step_dir="$(printf '%s/s%03d' "$run_dir" "$step")"
    mkdir -p "$step_dir"
    effective="$step_dir/effective_prompt.md"
    stdout_log="$step_dir/stdout.log"
    stderr_log="$step_dir/stderr.log"
    : > "$stdout_log"; : > "$stderr_log"
    if [[ "$handoff_enabled" -eq 1 ]]; then
      if [[ $step -gt 1 ]]; then
        prev_handoff="$(printf '%s/s%03d/handoff.md' "$run_dir" "$((step - 1))")"
        [[ -f "$prev_handoff" ]] && input_handoff="$prev_handoff"
      fi
      output_handoff="$step_dir/handoff.md"
      : > "$output_handoff"
    fi
    emit_effective_prompt "$step" "$agent_cmd" "$input_handoff" "$output_handoff" "$prompt" > "$effective"
    if [[ "$use_tmux" -eq 0 ]]; then
      set +e
      bash -c "$agent_cmd" < "$effective" > "$stdout_log" 2> "$stderr_log"
      code=$?
      set -e
      printf '%s\n' "$code" > "$step_dir/exit_code.txt"
    fi
  fi

  if [[ "$use_tmux" -eq 1 ]]; then
    effective_prompt="$(emit_effective_prompt "$step" "$agent_cmd" "$input_handoff" "$output_handoff" "$prompt")"
    tmux_cmd="$(build_tmux_step_command "$effective_prompt" "$agent_cmd" "$stdout_log" "$stderr_log")"
    window_name="$(build_tmux_window_name "$step" "$prompt")"
    if [[ "$tmux_created" -eq 0 ]]; then
      tmux new-session -d -s "$tmux_session_name" -n "$window_name" bash -c "$tmux_cmd"
      configure_tmux_window "$tmux_session_name" "$window_name"
      tmux_created=1
    else
      tmux new-window -d -t "$tmux_session_name" -n "$window_name" bash -c "$tmux_cmd"
      configure_tmux_window "$tmux_session_name" "$window_name"
    fi
    code="$(wait_for_tmux_window "$tmux_session_name" "$window_name")"
    [[ -n "$code" ]] || code=1
    if [[ -n "$step_dir" ]]; then
      printf '%s\n' "$code" > "$step_dir/exit_code.txt"
    fi
  elif [[ -z "$session_dir" ]]; then
    set +e
    emit_effective_prompt "$step" "$agent_cmd" "$input_handoff" "$output_handoff" "$prompt" | bash -c "$agent_cmd"
    code=$?
    set -e
  fi

  end_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  elapsed=$(( $(date +%s) - start_epoch ))
  echo "[step $step] done exit=$code elapsed=${elapsed}s"
  if [[ -n "$loop_log" ]]; then
    printf '%s step=%d prompt=%s agent_cmd=%q exit=%d elapsed_s=%d\n' \
      "$end_iso" "$step" "$prompt" "$agent_cmd" "$code" "$elapsed" >> "$loop_log"
  fi
done

echo "Loop finished after $max_steps steps."
