#!/usr/bin/env bats

setup() {
  SKILL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT_PATH="$SKILL_ROOT/scripts/roster"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roster-tests.XXXXXX")"
  STUB_BIN_DIR="$TEST_ROOT/bin"
  mkdir -p "$STUB_BIN_DIR"

  create_tmux_stub

  export PATH="$STUB_BIN_DIR:$PATH"
  export TMUX='/tmp/test-tmux,1,0'
}

teardown() {
  rm -rf "$TEST_ROOT"
}

create_tmux_stub() {
  cat >"$STUB_BIN_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd=${1:-}
shift || true

case "$cmd" in
  list-panes)
    if [[ "${TMUX_LIST_PANES_STATUS:-0}" != 0 ]]; then
      printf 'tmux unavailable\n' >&2
      exit "$TMUX_LIST_PANES_STATUS"
    fi
    printf '%%42\tresearch\tcodex-main\t@7\t2\t1\t/work/research\tcodex\n'
    printf '%%43\tresearch\tcodex-review\t@8\t3\t0\t/work/research\tzsh\n'
    printf '%%44\tresearch\teditor\t@9\t4\t0\t/work/research\tvim\n'
    printf '%%45\tops\tcodex-main\t@10\t1\t0\t/work/ops\tcodex\n'
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$STUB_BIN_DIR/tmux"
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

assert_not_contains() {
  local haystack=$1
  local needle=$2

  [[ "$haystack" != *"$needle"* ]] || {
    printf 'expected output not to contain:\n%s\nactual:\n%s\n' "$needle" "$haystack" >&2
    return 1
  }
}

@test "list prints panes whose command is codex" {
  run "$SCRIPT_PATH" list

  assert_success
  assert_contains "$output" 'pane: %42'
  assert_contains "$output" 'agent_kind: codex'
  assert_contains "$output" 'command: codex'
  assert_contains "$output" 'detection: command'
}

@test "missing command fails clearly" {
  run "$SCRIPT_PATH"

  assert_failure
  assert_contains "$output" 'roster: missing command'
  assert_contains "$output" 'usage:'
}

@test "get without query fails clearly" {
  run "$SCRIPT_PATH" get

  assert_failure
  assert_contains "$output" 'roster: get requires a query'
}

@test "list prints panes whose window name starts with codex dash" {
  run "$SCRIPT_PATH" list

  assert_success
  assert_contains "$output" 'pane: %43'
  assert_contains "$output" 'window: codex-review'
  assert_contains "$output" 'command: zsh'
  assert_contains "$output" 'detection: window-name'
}

@test "list excludes ordinary panes by default" {
  run "$SCRIPT_PATH" list

  assert_success
  assert_not_contains "$output" 'pane: %44'
  assert_not_contains "$output" 'window: editor'
}

@test "list all includes ordinary panes as unknown" {
  run "$SCRIPT_PATH" list --all

  assert_success
  assert_contains "$output" 'pane: %44'
  assert_contains "$output" 'agent_kind: unknown'
  assert_contains "$output" 'window: editor'
  assert_contains "$output" 'detection: none'
}

@test "get pane id resolves exactly one detected agent pane" {
  run "$SCRIPT_PATH" get %42

  assert_success
  assert_contains "$output" 'pane: %42'
  assert_contains "$output" 'window: codex-main'
  assert_contains "$output" 'detection: command'
}

@test "get window name resolves exactly one detected agent pane" {
  run "$SCRIPT_PATH" get codex-review

  assert_success
  assert_contains "$output" 'pane: %43'
  assert_contains "$output" 'window: codex-review'
  assert_contains "$output" 'detection: window-name'
}

@test "get fails clearly when no detected agent pane matches" {
  run "$SCRIPT_PATH" get editor

  assert_failure
  assert_contains "$output" 'roster: no matching panes for query: editor'
}

@test "get fails clearly when multiple detected agent panes match" {
  run "$SCRIPT_PATH" get codex

  assert_failure
  assert_contains "$output" 'roster: multiple matching panes for query: codex; choose a more precise query, preferably a pane id'
  assert_contains "$output" $'pane\tsession\twindow_index\tpane_index\twindow\tcwd\tcommand\tdetection'
  assert_contains "$output" $'%42\tresearch\t2\t1\tcodex-main\t/work/research\tcodex\tcommand'
  assert_contains "$output" $'%45\tops\t1\t0\tcodex-main\t/work/ops\tcodex\tcommand'
}

@test "get all can resolve a non-agent pane" {
  run "$SCRIPT_PATH" get --all editor

  assert_success
  assert_contains "$output" 'agent_kind: unknown'
  assert_contains "$output" 'pane: %44'
  assert_contains "$output" 'window: editor'
  assert_contains "$output" 'detection: none'
}

@test "tmux failures are reported clearly" {
  export TMUX_LIST_PANES_STATUS=1

  run "$SCRIPT_PATH" list

  assert_failure
  assert_contains "$output" 'roster: tmux pane listing failed: tmux unavailable'
}
