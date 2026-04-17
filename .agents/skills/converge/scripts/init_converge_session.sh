#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <task-slug> [sessions_root]" >&2
  exit 1
fi

TASK_SLUG="$1"
SESSIONS_ROOT="${2:-./converge-sessions}"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
SESSION_ID="${TIMESTAMP}-${TASK_SLUG}"
SESSION_DIR="${SESSIONS_ROOT}/${SESSION_ID}"

mkdir -p "${SESSION_DIR}/round_1"

if [[ ! -f "${SESSION_DIR}/goal.md" ]]; then
  cat > "${SESSION_DIR}/goal.md" <<'EOF'
# Goal

## Objective
<fill this>

## Success Criteria
- [ ] <fill this>

## Constraints
- <fill this>

## Non-goals
- <fill this>

## Max Rounds
3
EOF
fi

echo "Created session: ${SESSION_DIR}"
echo "Created round: ${SESSION_DIR}/round_1"
