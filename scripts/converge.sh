#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
converge.sh - run rotating agent loop with per-step handoff

USAGE
  converge.sh --session-dir <path> --prompt-list <path> --agent-cmd "<command>" [--max-steps <n>]

REQUIRED
  --session-dir   Session root for run artifacts.
  --prompt-list   File with one prompt path per line (rotation order).
  --agent-cmd     Agent command, e.g. "codex exec" or "claude".

OPTIONAL
  --max-steps     Number of loop iterations (default: 10).
  -h, --help      Show this help message.

PROMPT LIST RULES
  - Empty lines are ignored.
  - Lines starting with # are ignored.
  - Relative prompt paths are resolved from the prompt-list directory.

EXAMPLES
  converge.sh --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "codex exec --dangerously-bypass-approvals-and-sandbox -" --max-steps 6
  converge.sh --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "claude -p --permission-mode bypassPermissions"
  converge.sh --session-dir ./session --prompt-list ./prompts.txt --agent-cmd "cursor-agent -p --yolo --trust --approve-mcps"
EOF
}

session_dir="" prompt_list="" agent_cmd="" max_steps=10
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-dir) session_dir="${2:-}"; shift 2 ;;
    --prompt-list) prompt_list="${2:-}"; shift 2 ;;
    --agent-cmd) agent_cmd="${2:-}"; shift 2 ;;
    --max-steps) max_steps="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -n "$session_dir" && -n "$prompt_list" && -n "$agent_cmd" ]] || { usage >&2; exit 1; }
[[ -f "$prompt_list" ]] || { echo "Prompt list not found: $prompt_list" >&2; exit 1; }
[[ "$max_steps" =~ ^[0-9]+$ && "$max_steps" -gt 0 ]] || { echo "--max-steps must be a positive integer." >&2; exit 1; }

session_dir="$(mkdir -p "$session_dir" && cd "$session_dir" && pwd)"
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

run_dir="$session_dir/run"
loop_log="$run_dir/loop/loop.log"
mkdir -p "$run_dir/loop"
touch "$loop_log"

echo "Starting agent loop"
echo "session_dir=$session_dir"
echo "prompt_count=${#prompts[@]}"
echo "max_steps=$max_steps"
echo "agent_cmd=$agent_cmd"

for ((step=1; step<=max_steps; step++)); do
  prompt="${prompts[$(( (step - 1) % ${#prompts[@]} ))]}"
  step_dir="$(printf '%s/s%03d' "$run_dir" "$step")"
  mkdir -p "$step_dir"

  input_handoff=""
  if [[ $step -gt 1 ]]; then
    prev_handoff="$(printf '%s/s%03d/handoff.md' "$run_dir" "$((step - 1))")"
    [[ -f "$prev_handoff" ]] && input_handoff="$prev_handoff"
  fi
  output_handoff="$step_dir/handoff.md"
  effective="$step_dir/effective_prompt.md"
  stdout_log="$step_dir/stdout.log"
  stderr_log="$step_dir/stderr.log"
  exit_file="$step_dir/exit_code.txt"
  : > "$output_handoff"; : > "$stdout_log"; : > "$stderr_log"

  {
    echo "# Runtime Protocol"; echo
    echo "- step: $step"
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

  start_epoch="$(date +%s)"
  start_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "[step $step] start prompt=$(basename "$prompt") time=$start_iso"

  set +e
  bash -lc "$agent_cmd" < "$effective" > "$stdout_log" 2> "$stderr_log"
  code=$?
  set -e
  printf '%s\n' "$code" > "$exit_file"

  end_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  elapsed=$(( $(date +%s) - start_epoch ))
  echo "[step $step] done exit=$code elapsed=${elapsed}s"
  printf '%s step=%d prompt=%s exit=%d elapsed_s=%d\n' \
    "$end_iso" "$step" "$prompt" "$code" "$elapsed" >> "$loop_log"
done

echo "Loop finished after $max_steps steps."
