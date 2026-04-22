#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONVERGE_SCRIPT="$REPO_ROOT/scripts/converge.sh"

usage() {
  cat <<'EOF'
converge_tmux_smoke.sh - lightweight manual smoke launcher

USAGE
  tests/converge_tmux_smoke.sh [--keep]

OPTIONS
  --keep    Keep temporary files and tmux session after script exits.
EOF
}

KEEP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

command -v tmux >/dev/null 2>&1 || { echo "tmux is required." >&2; exit 1; }
[[ -x "$CONVERGE_SCRIPT" ]] || { echo "converge script not executable: $CONVERGE_SCRIPT" >&2; exit 1; }

tmp_root="$(mktemp -d)"
prompts_dir="$tmp_root/prompts"
agents_dir="$tmp_root/agents"
session_dir="$tmp_root/session"
tmux_session="converge-smoke-$$"

cleanup() {
  if [[ "$KEEP" -eq 0 ]]; then
    tmux kill-session -t "$tmux_session" >/dev/null 2>&1 || true
    rm -rf "$tmp_root"
  fi
}
trap cleanup EXIT

mkdir -p "$prompts_dir" "$agents_dir"

cat > "$prompts_dir/builder.md" <<'EOF'
Builder prompt body.
EOF

cat > "$prompts_dir/reviewer.md" <<'EOF'
Reviewer prompt body.
EOF

cat > "$agents_dir/agent-a.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
payload="$(cat)"
step="$(printf '%s\n' "$payload" | sed -n 's/^- step: //p' | sed -n '1p')"
printf 'agent-a step=%s\n' "${step:-unknown}"
printf 'agent-a stderr step=%s\n' "${step:-unknown}" >&2
exit 0
EOF
chmod +x "$agents_dir/agent-a.sh"

cat > "$agents_dir/agent-b.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
payload="$(cat)"
step="$(printf '%s\n' "$payload" | sed -n 's/^- step: //p' | sed -n '1p')"
printf 'agent-b step=%s\n' "${step:-unknown}"
printf 'agent-b stderr step=%s\n' "${step:-unknown}" >&2
exit 7
EOF
chmod +x "$agents_dir/agent-b.sh"

echo "Launching converge smoke run..."
echo "tmp_root=$tmp_root"
echo "session_dir=$session_dir"
echo "tmux_session=$tmux_session"
echo

bash "$CONVERGE_SCRIPT" \
  --session-dir "$session_dir" \
  --prompt "Inline prompt body." \
  --prompt-file "$prompts_dir/builder.md" \
  --prompt-file "$prompts_dir/reviewer.md" \
  --agent-cmd "$agents_dir/agent-a.sh" \
  --agent-cmd "$agents_dir/agent-b.sh" \
  --max-steps 4 \
  --tmux \
  --tmux-session-name "$tmux_session"

cat <<EOF

Run completed. Manual checks:
- Attach tmux (if session still present): tmux attach -t $tmux_session
- Step dirs: $session_dir/run/s001 ... s004
- Effective prompts: $session_dir/run/s00X/effective_prompt.md
- Agent logs: $session_dir/run/s00X/stdout.log and stderr.log
- Exit codes: $session_dir/run/s00X/exit_code.txt
- Loop log: $session_dir/run/loop/loop.log
- Handoff files should exist by default: $session_dir/run/s00X/handoff.md

To keep artifacts after this script exits, rerun with --keep.
EOF
