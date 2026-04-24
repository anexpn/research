#!/usr/bin/env bash

set -euo pipefail

readonly HISTORY_LIMIT=12

usage() {
  cat <<'EOF'
Usage: commit.sh [options]

Options:
  --agent codex|claude|cursor-agent
  --vcs git|jj
  --style conventional|repo|prompt
  --template-file PATH
  --prompt TEXT
  --agent-arg ARG
  -h, --help

Template placeholders:
  {{VCS}}
  {{STYLE_MODE}}
  {{STYLE_INSTRUCTIONS}}
  {{USER_GUIDANCE}}
  {{RECENT_SUBJECTS}}
  {{DIFF}}
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

format_command() {
  local formatted
  printf -v formatted '%q ' "$@"
  printf '%s' "${formatted% }"
}

trim_edge_blank_lines() {
  awk '
    { lines[NR] = $0 }
    END {
      first = 1
      while (first <= NR && lines[first] ~ /^[[:space:]]*$/) {
        first++
      }

      last = NR
      while (last >= first && lines[last] ~ /^[[:space:]]*$/) {
        last--
      }

      for (i = first; i <= last; i++) {
        print lines[i]
      }
    }
  '
}

strip_code_fences() {
  awk '
    NR == 1 && $0 ~ /^```/ {
      fenced_output = 1
      next
    }

    !fenced_output {
      print
      next
    }

    fenced_output && $0 ~ /^```[[:space:]]*$/ {
      exit
    }

    { print }
  '
}

normalize_commit_message() {
  local raw_message=$1
  local normalized
  local subject
  local body

  raw_message=${raw_message//$'\r'/}
  normalized="$(printf '%s' "$raw_message" | trim_edge_blank_lines | strip_code_fences | trim_edge_blank_lines)"
  subject="${normalized%%$'\n'*}"
  subject="$(printf '%s' "$subject" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  if [[ "$normalized" == *$'\n'* ]]; then
    body="${normalized#*$'\n'}"
    printf '%s\n%s' "$subject" "$body"
  else
    printf '%s' "$subject"
  fi
}

default_template() {
  cat <<'EOF'
You are generating a commit message for the selected change.

Selected VCS: {{VCS}}
Style mode: {{STYLE_MODE}}

Style instructions:
{{STYLE_INSTRUCTIONS}}

Additional user guidance:
{{USER_GUIDANCE}}

Recent repo subjects:
{{RECENT_SUBJECTS}}

Diff to summarize:
{{DIFF}}

Output contract:
- Return only the commit message.
- The first line must be the subject.
- Include a blank line and body only when warranted by the diff.
- No code fences.
- No explanation.
- No surrounding commentary.
EOF
}

render_template() {
  local template=$1
  local vcs_name=$2
  local style_name=$3
  local style_instructions=$4
  local user_guidance=$5
  local recent_subjects=$6
  local diff_text=$7
  local rendered=
  local prefix
  local remainder
  local placeholder
  local open='{{'
  local close='}}'

  remainder=$template
  while [[ "$remainder" == *"$open"* ]]; do
    prefix=${remainder%%"$open"*}
    rendered+=$prefix
    remainder=${remainder#"$prefix"}
    remainder=${remainder#"$open"}

    if [[ "$remainder" != *"$close"* ]]; then
      rendered+=$open$remainder
      remainder=
      break
    fi

    placeholder=${remainder%%"$close"*}
    remainder=${remainder#"$placeholder"}
    remainder=${remainder#"$close"}

    case "$placeholder" in
      VCS)
        rendered+=$vcs_name
        ;;
      STYLE_MODE)
        rendered+=$style_name
        ;;
      STYLE_INSTRUCTIONS)
        rendered+=$style_instructions
        ;;
      USER_GUIDANCE)
        rendered+=$user_guidance
        ;;
      RECENT_SUBJECTS)
        rendered+=$recent_subjects
        ;;
      DIFF)
        rendered+=$diff_text
        ;;
      *)
        rendered+=$open$placeholder$close
        ;;
    esac
  done

  rendered+=$remainder
  printf '%s' "$rendered"
}

detect_vcs() {
  if [[ -n "$requested_vcs" ]]; then
    printf '%s' "$requested_vcs"
    return
  fi

  if jj root >/dev/null 2>&1; then
    printf 'jj'
    return
  fi

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    printf 'git'
    return
  fi

  die 'Could not detect a supported VCS. Use --vcs git or --vcs jj.'
}

infer_agent_name() {
  local candidate

  for candidate in codex claude cursor-agent; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return
    fi
  done

  die 'Could not infer an agent preset. Looked for codex, claude, then cursor-agent on PATH. Use --agent to choose explicitly.'
}

collect_diff() {
  local vcs_name=$1
  local diff_text

  case "$vcs_name" in
    git)
      if git diff --cached --quiet; then
        die 'No staged changes found for git. Stage changes first or use --vcs jj.'
      fi
      diff_text="$(git diff --cached)"
      ;;
    jj)
      diff_text="$(jj diff --git)"
      if [[ -z "$diff_text" ]]; then
        die 'No working-copy changes found for jj.'
      fi
      ;;
    *)
      die "Unsupported VCS: $vcs_name"
      ;;
  esac

  printf '%s' "$diff_text"
}

collect_recent_subjects() {
  local vcs_name=$1
  local subjects

  case "$vcs_name" in
    git)
      subjects="$(git log --format=%s -n "$HISTORY_LIMIT" 2>/dev/null || true)"
      ;;
    jj)
      subjects="$(jj log -r "ancestors(@-, $HISTORY_LIMIT)" -n "$HISTORY_LIMIT" --no-graph -T 'description.first_line() ++ "\n"' 2>/dev/null || true)"
      ;;
    *)
      die "Unsupported VCS: $vcs_name"
      ;;
  esac

  subjects="$(printf '%s' "$subjects" | trim_edge_blank_lines)"
  if [[ -z "$subjects" ]]; then
    printf '(none)'
  else
    printf '%s' "$subjects"
  fi
}

style_instructions_for() {
  case "$style_mode" in
    conventional)
      cat <<'EOF'
Use conventional commits for the subject line.
Recent repo subjects are secondary context only.
Conventional commits take priority unless another style mode is explicitly selected.
EOF
      ;;
    repo)
      cat <<'EOF'
Learn the dominant pattern in the recent repo subjects and follow that pattern.
Recent repo subjects are the primary style signal in this mode.
Do not force a conventional commit if the repo pattern points elsewhere.
EOF
      ;;
    prompt)
      cat <<'EOF'
Follow the user guidance below as the primary style instruction.
Use recent repo subjects only as secondary context.
EOF
      ;;
    *)
      die "Unsupported style mode: $style_mode"
      ;;
  esac
}

resolve_agent_command() {
  local agent_name=$1

  agent_input_mode=
  agent_command=()

  case "$agent_name" in
    codex)
      agent_input_mode=stdin
      agent_command=(codex exec --dangerously-bypass-approvals-and-sandbox)
      ;;
    claude)
      agent_input_mode=argv
      agent_command=(claude -p --permission-mode bypassPermissions)
      ;;
    cursor-agent)
      agent_input_mode=argv
      agent_command=(cursor-agent -p --yolo --trust --approve-mcps)
      ;;
    *)
      die "Unsupported or missing agent preset: $agent_name"
      ;;
  esac

  if ! command -v "${agent_command[0]}" >/dev/null 2>&1; then
    die "Agent binary not found on PATH: ${agent_command[0]}"
  fi
}

run_agent() {
  local prompt_text=$1
  local -a cmd
  local output
  local resolved_command

  resolve_agent_command "$agent_name"
  cmd=("${agent_command[@]}")
  if [[ ${#agent_args[@]} -gt 0 ]]; then
    cmd+=("${agent_args[@]}")
  fi

  if [[ "$agent_input_mode" == "stdin" ]]; then
    cmd+=(-)
  fi

  resolved_command="$(format_command "${cmd[@]}")"

  if [[ "$agent_input_mode" == "stdin" ]]; then
    if ! output="$(printf '%s' "$prompt_text" | "${cmd[@]}")"; then
      die "Agent command failed: $resolved_command"
    fi
  else
    if ! output="$("${cmd[@]}" "$prompt_text" < /dev/null)"; then
      die "Agent command failed: $resolved_command"
    fi
  fi

  printf '%s' "$output"
}

write_message_file() {
  local message_text=$1

  message_file="$(mktemp "${TMPDIR:-/tmp}/commit-sh-message.XXXXXX")"
  printf '%s\n' "$message_text" >"$message_file"
}

perform_commit() {
  local vcs_name=$1
  local message_text=$2

  write_message_file "$message_text"

  case "$vcs_name" in
    git)
      if ! git commit -F "$message_file"; then
        die 'git commit failed. Check repository state and staged changes, then try again.'
      fi
      ;;
    jj)
      if ! jj commit -m "$(cat "$message_file")"; then
        die 'jj commit failed. Check repository state and working-copy changes, then try again.'
      fi
      ;;
    *)
      die "Unsupported VCS: $vcs_name"
      ;;
  esac
}

requested_vcs=
agent_name=
style_mode=conventional
template_file=
user_prompt=
message_file=
agent_input_mode=
agent_command=()
agent_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      [[ $# -ge 2 ]] || die '--agent requires a value.'
      agent_name=$2
      shift 2
      ;;
    --vcs)
      [[ $# -ge 2 ]] || die '--vcs requires a value.'
      requested_vcs=$2
      shift 2
      ;;
    --style)
      [[ $# -ge 2 ]] || die '--style requires a value.'
      style_mode=$2
      shift 2
      ;;
    --template-file)
      [[ $# -ge 2 ]] || die '--template-file requires a value.'
      template_file=$2
      shift 2
      ;;
    --prompt)
      [[ $# -ge 2 ]] || die '--prompt requires a value.'
      user_prompt=$2
      shift 2
      ;;
    --agent-arg)
      [[ $# -ge 2 ]] || die '--agent-arg requires a value.'
      agent_args+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$agent_name" ]]; then
  agent_name="$(infer_agent_name)"
fi

case "$style_mode" in
  conventional|repo|prompt)
    ;;
  *)
    die "Unsupported style mode: $style_mode"
    ;;
esac

if [[ -n "$requested_vcs" ]]; then
  case "$requested_vcs" in
    git|jj)
      ;;
    *)
      die "Unsupported VCS: $requested_vcs"
      ;;
  esac
fi

if [[ "$style_mode" == "prompt" && -z "$user_prompt" ]]; then
  die '--style prompt requires --prompt.'
fi

if [[ -n "$template_file" && ! -r "$template_file" ]]; then
  die "Template file is not readable: $template_file"
fi

cleanup() {
  if [[ -n "$message_file" && -f "$message_file" ]]; then
    rm -f "$message_file"
  fi
}

trap cleanup EXIT

selected_vcs="$(detect_vcs)"
diff_text="$(collect_diff "$selected_vcs")"
recent_subjects="$(collect_recent_subjects "$selected_vcs")"
style_instructions="$(style_instructions_for)"

if [[ -n "$template_file" ]]; then
  template_contents="$(<"$template_file")"
else
  template_contents="$(default_template)"
fi

if [[ -z "$user_prompt" ]]; then
  user_guidance='(none)'
else
  user_guidance=$user_prompt
fi

prompt_text="$(render_template \
  "$template_contents" \
  "$selected_vcs" \
  "$style_mode" \
  "$style_instructions" \
  "$user_guidance" \
  "$recent_subjects" \
  "$diff_text")"

raw_message="$(run_agent "$prompt_text")"
normalized_message="$(normalize_commit_message "$raw_message")"

if [[ -z "$normalized_message" ]]; then
  die 'Agent returned an empty commit message.'
fi

normalized_subject="${normalized_message%%$'\n'*}"
normalized_subject="$(printf '%s' "$normalized_subject" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [[ -z "$normalized_subject" ]]; then
  die 'Agent returned an empty subject line.'
fi

perform_commit "$selected_vcs" "$normalized_message"
