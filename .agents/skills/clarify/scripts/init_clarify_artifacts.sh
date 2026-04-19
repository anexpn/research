#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <session_dir>" >&2
  exit 1
fi

SESSION_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${SKILL_DIR}/templates"

mkdir -p "${SESSION_DIR}"

copy_if_missing() {
  local src="$1"
  local dst="$2"
  if [[ -f "${dst}" ]]; then
    echo "Keeping existing: ${dst}"
    return
  fi
  cp "${src}" "${dst}"
  echo "Created: ${dst}"
}

copy_if_missing "${TEMPLATE_DIR}/goal.template.md" "${SESSION_DIR}/goal.md"
copy_if_missing "${TEMPLATE_DIR}/verification_spec.template.md" "${SESSION_DIR}/verification_spec.md"

echo "Clarify artifacts ready in: ${SESSION_DIR}"
