#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <round_dir>" >&2
  exit 1
fi

ROUND_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${SKILL_DIR}/templates"

if [[ ! -d "${ROUND_DIR}" ]]; then
  echo "Round directory not found: ${ROUND_DIR}" >&2
  exit 1
fi

mkdir -p "${ROUND_DIR}/run"

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

copy_if_missing "${TEMPLATE_DIR}/builder_report.template.md" "${ROUND_DIR}/builder_report.md"
copy_if_missing "${TEMPLATE_DIR}/inspector_review.template.md" "${ROUND_DIR}/inspector_review.md"
copy_if_missing "${TEMPLATE_DIR}/judge_resolution.template.md" "${ROUND_DIR}/judge_resolution.md"

echo "Round scaffold complete: ${ROUND_DIR}"
