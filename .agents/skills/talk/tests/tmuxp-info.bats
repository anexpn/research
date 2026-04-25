#!/usr/bin/env bats

setup() {
  SKILL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT_PATH="$SKILL_ROOT/scripts/tmuxp-info"
  FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  cat >"$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
  display-message)
    printf '%%91\n'
    ;;
  list-panes)
    printf 'node\t@56\t%%91\t1\t/workspace/research\n'
    printf 'codex-review\t@58\t%%93\t1\t/workspace/research\n'
    printf 'codex-review-old\t@59\t%%94\t0\t/tmp/archive\n'
    printf 'zsh\t@8\t%%38\t1\t/home/user/.emacs.d\n'
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/tmux"
  PATH="$FAKE_BIN:$PATH"
}

assert_success() {
  if [[ "$status" -ne 0 ]]; then
    printf 'expected success, got %s\n%s\n' "$status" "$output" >&2
    return 1
  fi
}

assert_failure() {
  if [[ "$status" -eq 0 ]]; then
    printf 'expected failure, got success\n%s\n' "$output" >&2
    return 1
  fi
}

assert_contains() {
  local haystack=$1
  local needle=$2

  [[ "$haystack" == *"$needle"* ]] || {
    printf 'expected output to contain:\n%s\nactual:\n%s\n' "$needle" "$haystack" >&2
    return 1
  }
}

@test "lists current pane and available panes" {
  run "$SCRIPT_PATH"

  assert_success
  assert_contains "$output" 'current-pane: %91'
  assert_contains "$output" $'active\tpane-id\twindow-id\twindow\tpath'
  assert_contains "$output" $'*\t%93\t@58\tcodex-review\t/workspace/research'
}

@test "resolves a unique pane id target" {
  run "$SCRIPT_PATH" %93

  assert_success
  assert_contains "$output" 'current-pane: %91'
  assert_contains "$output" 'query: %93'
  assert_contains "$output" 'target: %93'
  assert_contains "$output" $'*\t%93\t@58\tcodex-review\t/workspace/research'
}

@test "resolves a unique window name target" {
  run "$SCRIPT_PATH" node

  assert_success
  assert_contains "$output" 'target: %91'
  assert_contains "$output" $'*\t%91\t@56\tnode\t/workspace/research'
}

@test "reports no matching pane" {
  run "$SCRIPT_PATH" missing-agent

  assert_failure
  assert_contains "$output" 'query: missing-agent'
  assert_contains "$output" 'tmuxp-info: no matching tmux pane'
}

@test "reports ambiguous matches with candidate panes" {
  run "$SCRIPT_PATH" codex-review

  assert_failure
  assert_contains "$output" 'multiple matching tmux panes; choose an explicit pane id'
  assert_contains "$output" $'*\t%93\t@58\tcodex-review\t/workspace/research'
  assert_contains "$output" $'-\t%94\t@59\tcodex-review-old\t/tmp/archive'
}
