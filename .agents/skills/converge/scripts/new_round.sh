#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <session_dir>" >&2
  exit 1
fi

SESSION_DIR="$1"

if [[ ! -d "${SESSION_DIR}" ]]; then
  echo "Session directory not found: ${SESSION_DIR}" >&2
  exit 1
fi

LAST_ROUND="$(ls -1 "${SESSION_DIR}" | rg '^round_[0-9]+$' | sort -V | tail -n 1 || true)"

if [[ -z "${LAST_ROUND}" ]]; then
  NEXT_NUM=1
else
  LAST_NUM="${LAST_ROUND#round_}"
  NEXT_NUM=$((LAST_NUM + 1))
fi

NEXT_DIR="${SESSION_DIR}/round_${NEXT_NUM}"

if [[ -d "${NEXT_DIR}" ]]; then
  echo "Round already exists: ${NEXT_DIR}" >&2
  exit 1
fi

mkdir -p "${NEXT_DIR}/run"
echo "Created: ${NEXT_DIR}"
echo "Created: ${NEXT_DIR}/run"
