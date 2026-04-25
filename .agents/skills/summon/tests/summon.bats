#!/usr/bin/env bats

setup() {
  SKILL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT_PATH="$SKILL_ROOT/scripts/summon"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/summon-tests.XXXXXX")"
  STUB_BIN_DIR="$TEST_ROOT/bin"
  SYSTEM_BIN_DIR="$TEST_ROOT/system-bin"
  TMUX_LOG="$TEST_ROOT/tmux.log"
  TMUX_WINDOWS_FILE="$TEST_ROOT/windows"
  mkdir -p "$STUB_BIN_DIR" "$SYSTEM_BIN_DIR"

  link_system_command bash
  link_system_command cat
  link_system_command date
  link_system_command mkdir
  link_system_command pwd
  link_system_command rm

  create_codex_stub
  create_tmux_stub

  export PATH="$STUB_BIN_DIR:$SYSTEM_BIN_DIR"
  export TMUX_LOG
  export TMUX_WINDOWS_FILE
  export TMUX_SESSION_NAME=test-session
  export TMUX_WINDOW_NAME=test-window
  export TMUX_NEW_WINDOW_PANE='%42'
  export TMUX_SPLIT_WINDOW_PANE='%43'
  export TMUX_NEW_SESSION_PANE='%44'
  export TMUX='/tmp/test-tmux,1,0'
}

teardown() {
  rm -rf "$TEST_ROOT"
}

link_system_command() {
  local name=$1
  local source_path

  source_path="$(command -v "$name")"
  ln -s "$source_path" "$SYSTEM_BIN_DIR/$name"
}

create_codex_stub() {
  cat >"$STUB_BIN_DIR/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB_BIN_DIR/codex"
}

create_tmux_stub() {
  cat >"$STUB_BIN_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

socket=''
if [[ "${1:-}" == '-L' ]]; then
  socket=$2
  shift 2
fi

cmd=${1:-}
shift || true

{
  printf 'socket=%s cmd=%s' "$socket" "$cmd"
  for arg in "$@"; do
    printf ' arg=%s' "$arg"
  done
  printf '\n'
} >>"$TMUX_LOG"

case "$cmd" in
  display-message)
    if [[ "${*: -1}" == '#S' ]]; then
      printf '%s\n' "${TMUX_SESSION_NAME:-test-session}"
    else
      printf '%s\n' "${TMUX_WINDOW_NAME:-test-window}"
    fi
    ;;
  list-windows)
    if [[ -f "${TMUX_WINDOWS_FILE:-}" ]]; then
      cat "$TMUX_WINDOWS_FILE"
    fi
    ;;
  new-window)
    printf '%s\n' "${TMUX_NEW_WINDOW_PANE:-%42}"
    ;;
  split-window)
    printf '%s\n' "${TMUX_SPLIT_WINDOW_PANE:-%43}"
    ;;
  select-pane)
    ;;
  has-session)
    exit "${TMUX_HAS_SESSION_STATUS:-1}"
    ;;
  new-session)
    printf '%s\n' "${TMUX_NEW_SESSION_PANE:-%44}"
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

@test "dry-run prints intended Codex command and metadata shape" {
  unset TMUX

  run "$SCRIPT_PATH" codex --dry-run -- "hello"

  assert_success
  assert_contains "$output" 'agent_kind: codex'
  assert_contains "$output" 'name: codex-'
  assert_contains "$output" 'mode: shared'
  assert_contains "$output" 'session: dry-run'
  assert_contains "$output" 'pane: %dry-run'
  assert_contains "$output" 'talk_target: %dry-run'
  assert_contains "$output" 'dry_run: true'
  assert_contains "$output" "command: codex --cd $PWD hello"
}

@test "shared window mode creates a tmux window and prints a talk target" {
  run "$SCRIPT_PATH" codex --name codex-review -- "Review the diff"

  assert_success
  assert_contains "$output" 'agent_kind: codex'
  assert_contains "$output" 'name: codex-review'
  assert_contains "$output" 'mode: shared'
  assert_contains "$output" 'session: test-session'
  assert_contains "$output" 'window: codex-review'
  assert_contains "$output" 'pane: %42'
  assert_contains "$output" 'talk_target: %42'
  assert_contains "$(cat "$TMUX_LOG")" 'cmd=new-window'
  assert_contains "$(cat "$TMUX_LOG")" 'arg=-n arg=codex-review'
  assert_contains "$(cat "$TMUX_LOG")" 'arg=codex --cd'
}

@test "shared pane mode splits the current tmux window and prints a talk target" {
  run "$SCRIPT_PATH" codex --name codex-pane --layout pane -- "Review the diff"

  assert_success
  assert_contains "$output" 'mode: shared'
  assert_contains "$output" 'window: test-window'
  assert_contains "$output" 'pane: %43'
  assert_contains "$output" 'talk_target: %43'
  assert_contains "$(cat "$TMUX_LOG")" 'cmd=split-window'
  assert_contains "$(cat "$TMUX_LOG")" 'cmd=select-pane arg=-t arg=%43 arg=-T arg=codex-pane'
}

@test "shared pane mode allows a colliding window name and uses it as the pane title" {
  printf 'codex-pane\n' >"$TMUX_WINDOWS_FILE"

  run "$SCRIPT_PATH" codex --name codex-pane --layout pane -- "Review the diff"

  assert_success
  assert_contains "$output" 'mode: shared'
  assert_contains "$output" 'window: test-window'
  assert_contains "$output" 'pane: %43'
  assert_contains "$(cat "$TMUX_LOG")" 'cmd=split-window'
  assert_contains "$(cat "$TMUX_LOG")" 'cmd=select-pane arg=-t arg=%43 arg=-T arg=codex-pane'
}

@test "isolated mode uses socket and creates a session when missing" {
  unset TMUX

  run "$SCRIPT_PATH" codex \
    --mode isolated \
    --socket summon-test \
    --session isolated-session \
    --name codex-isolated \
    -- "Start here"

  assert_success
  assert_contains "$output" 'mode: isolated'
  assert_contains "$output" 'socket: summon-test'
  assert_contains "$output" 'session: isolated-session'
  assert_contains "$output" 'pane: %44'
  [[ "$output" != *'talk_target:'* ]]
  assert_contains "$(cat "$TMUX_LOG")" 'socket=summon-test cmd=has-session'
  assert_contains "$(cat "$TMUX_LOG")" 'socket=summon-test cmd=new-session'
}

@test "isolated mode reuses an existing session by creating a window" {
  unset TMUX
  export TMUX_HAS_SESSION_STATUS=0

  run "$SCRIPT_PATH" codex \
    --mode isolated \
    --socket summon-test \
    --session isolated-session \
    --name codex-isolated \
    -- "Start here"

  assert_success
  assert_contains "$output" 'pane: %42'
  assert_contains "$(cat "$TMUX_LOG")" 'socket=summon-test cmd=new-window'
}

@test "isolated mode defaults socket and session from the agent name" {
  unset TMUX

  run "$SCRIPT_PATH" codex --mode isolated --name codex-isolated -- "Start here"

  assert_success
  assert_contains "$output" 'socket: summon-codex-isolated'
  assert_contains "$output" 'session: codex-isolated'
  assert_contains "$(cat "$TMUX_LOG")" 'socket=summon-codex-isolated cmd=has-session'
}

@test "isolated mode requires an initial prompt" {
  unset TMUX

  run "$SCRIPT_PATH" codex --mode isolated --name codex-isolated

  assert_failure
  assert_contains "$output" 'summon: isolated mode requires an initial prompt'
}

@test "invalid working directory fails" {
  run "$SCRIPT_PATH" codex --cd "$TEST_ROOT/missing" --dry-run -- "hello"

  assert_failure
  assert_contains "$output" "summon: working directory does not exist: $TEST_ROOT/missing"
}

@test "unsupported agent kind fails" {
  run "$SCRIPT_PATH" claude --dry-run -- "hello"

  assert_failure
  assert_contains "$output" 'summon: unsupported agent kind: claude'
}

@test "name collision fails" {
  printf 'codex-review\n' >"$TMUX_WINDOWS_FILE"

  run "$SCRIPT_PATH" codex --name codex-review -- "Review the diff"

  assert_failure
  assert_contains "$output" 'summon: tmux window already exists in session test-session: codex-review'
}

@test "generated names are accepted when name is omitted" {
  run "$SCRIPT_PATH" codex --dry-run -- "hello"

  assert_success
  assert_contains "$output" 'name: codex-'
}

@test "missing tmux on PATH fails" {
  rm -f "$STUB_BIN_DIR/tmux"

  run "$SCRIPT_PATH" codex --dry-run -- "hello"

  assert_failure
  assert_contains "$output" 'summon: tmux is not on PATH'
}

@test "missing codex on PATH fails" {
  rm -f "$STUB_BIN_DIR/codex"

  run "$SCRIPT_PATH" codex --dry-run -- "hello"

  assert_failure
  assert_contains "$output" 'summon: codex is not on PATH'
}

@test "shared mode outside tmux fails" {
  unset TMUX

  run "$SCRIPT_PATH" codex --name codex-review -- "Review the diff"

  assert_failure
  assert_contains "$output" 'summon: shared mode requires running inside tmux'
}

@test "isolated mode rejects pane layout" {
  unset TMUX

  run "$SCRIPT_PATH" codex --mode isolated --layout pane --name codex-isolated -- "Start here"

  assert_failure
  assert_contains "$output" 'summon: isolated mode only supports --layout window'
}
