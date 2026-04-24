#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TEST_ROOT
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/commit-sh-tests.XXXXXX")"
  export STUB_BIN_DIR="$TEST_ROOT/bin"
  mkdir -p "$STUB_BIN_DIR"

  export AGENT_NAME_FILE="$TEST_ROOT/agent-name"
  export AGENT_ARGS_FILE="$TEST_ROOT/agent-args"
  export AGENT_STDIN_FILE="$TEST_ROOT/agent-stdin"
  export AGENT_OUTPUT_FILE="$TEST_ROOT/agent-output"
  export AGENT_EXIT_CODE=0

  create_agent_stub codex
  create_agent_stub claude
  create_agent_stub cursor-agent

  export PATH="$STUB_BIN_DIR:$PATH"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

create_agent_stub() {
  local name=$1
  cat >"$STUB_BIN_DIR/$name" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

printf '%s' "$(basename "$0")" >"$AGENT_NAME_FILE"
printf '%s\0' "$@" >"$AGENT_ARGS_FILE"
cat >"$AGENT_STDIN_FILE"

if [[ -n "${AGENT_OUTPUT_FILE:-}" && -f "$AGENT_OUTPUT_FILE" ]]; then
  cat "$AGENT_OUTPUT_FILE"
fi

exit "${AGENT_EXIT_CODE:-0}"
EOF
  chmod +x "$STUB_BIN_DIR/$name"
}

init_git_repo() {
  local repo=$1

  mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.name 'Test User'
  git -C "$repo" config user.email 'test@example.com'

  printf 'base\n' >"$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -qm 'chore: base'
}

init_jj_repo() {
  local repo=$1

  jj git init "$repo" >/dev/null
  jj -R "$repo" config set --repo user.name 'Test User' >/dev/null
  jj -R "$repo" config set --repo user.email 'test@example.com' >/dev/null

  printf 'base\n' >"$repo/file.txt"
  jj -R "$repo" commit -m 'chore: base' >/dev/null
}

set_agent_output() {
  printf '%s' "$1" >"$AGENT_OUTPUT_FILE"
}

run_in_repo() {
  local repo=$1
  shift
  (
    cd "$repo"
    "$PROJECT_ROOT/commit.sh" "$@"
  )
}

load_agent_args() {
  agent_args=()
  while IFS= read -r -d '' arg; do
    agent_args+=("$arg")
  done <"$AGENT_ARGS_FILE" || true
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

@test "VCS inference prefers jj in a colocated repo" {
  local repo="$TEST_ROOT/jj-prefers"
  init_jj_repo "$repo"
  printf 'working-copy change\n' >>"$repo/file.txt"
  set_agent_output 'feat: inferred jj'

  run run_in_repo "$repo" --agent codex

  assert_success
  [[ "$(jj -R "$repo" log -r @- -n 1 --no-graph -T 'description.first_line()')" == 'feat: inferred jj' ]]
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Selected VCS: jj'
}

@test "--vcs overrides inference in a colocated repo" {
  local repo="$TEST_ROOT/jj-git-override"
  init_jj_repo "$repo"
  printf 'staged change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'feat: explicit git'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_success
  [[ "$(git -C "$repo" log -1 --format=%s)" == 'feat: explicit git' ]]
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Selected VCS: git'
}

@test "git mode uses only staged diff" {
  local repo="$TEST_ROOT/git-staged-only"
  init_git_repo "$repo"
  printf 'staged change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  printf 'unstaged only\n' >"$repo/unstaged.txt"
  set_agent_output 'feat: staged only'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_success
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'file.txt'
  if [[ "$(cat "$AGENT_STDIN_FILE")" == *'unstaged.txt'* ]]; then
    printf 'unstaged file leaked into git diff prompt\n' >&2
    return 1
  fi
}

@test "git mode ignores unstaged changes when committing" {
  local repo="$TEST_ROOT/git-ignores-unstaged"
  init_git_repo "$repo"
  printf 'tracked\n' >"$repo/extra.txt"
  git -C "$repo" add extra.txt
  git -C "$repo" commit -qm 'chore: track extra'
  printf 'staged change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  printf 'left unstaged\n' >>"$repo/extra.txt"
  set_agent_output 'feat: staged commit'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_success
  [[ "$(git -C "$repo" diff --name-only)" == 'extra.txt' ]]
  [[ "$(git -C "$repo" show HEAD:file.txt)" == *'staged change'* ]]
}

@test "git mode fails with nothing staged" {
  local repo="$TEST_ROOT/git-empty"
  init_git_repo "$repo"
  printf 'unstaged only\n' >>"$repo/file.txt"
  set_agent_output 'feat: should not commit'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_failure
  assert_contains "$output" 'No staged changes found for git'
}

@test "jj mode uses working-copy diff" {
  local repo="$TEST_ROOT/jj-working-copy"
  init_jj_repo "$repo"
  printf 'working-copy change\n' >>"$repo/file.txt"
  set_agent_output 'feat: jj change'

  run run_in_repo "$repo" --agent codex --vcs jj

  assert_success
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'working-copy change'
  [[ "$(jj -R "$repo" log -r @- -n 1 --no-graph -T 'description.first_line()')" == 'feat: jj change' ]]
}

@test "jj mode fails with no diff" {
  local repo="$TEST_ROOT/jj-empty"
  init_jj_repo "$repo"
  set_agent_output 'feat: should not commit'

  run run_in_repo "$repo" --agent codex --vcs jj

  assert_failure
  assert_contains "$output" 'No working-copy changes found for jj'
}

@test "default style is conventional" {
  local repo="$TEST_ROOT/default-style"
  init_git_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'feat: default conventional'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_success
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Style mode: conventional'
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Conventional commits take priority'
}

@test "recent commit subjects are secondary context in conventional mode" {
  local repo="$TEST_ROOT/default-history"
  init_git_repo "$repo"
  printf 'two\n' >"$repo/file.txt"
  git -C "$repo" commit -am 'fix: second' -q
  printf 'three\n' >"$repo/file.txt"
  git -C "$repo" commit -am 'docs: third' -q
  printf 'staged change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'feat: history context'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_success
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Recent repo subjects are secondary context only.'
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'fix: second'
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'docs: third'
}

@test "--style repo follows repo history as the main style signal" {
  local repo="$TEST_ROOT/repo-style"
  init_git_repo "$repo"
  printf 'two\n' >"$repo/file.txt"
  git -C "$repo" commit -am 'Refine widget loading' -q
  printf 'staged change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'Refine wrapper execution'

  run run_in_repo "$repo" --agent codex --vcs git --style repo

  assert_success
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Style mode: repo'
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Recent repo subjects are the primary style signal'
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Refine widget loading'
}

@test "--style prompt requires and uses user guidance" {
  local repo="$TEST_ROOT/prompt-style"
  init_git_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'release: guided'

  run run_in_repo "$repo" --agent codex --vcs git --style prompt --prompt 'Use a release: prefix'

  assert_success
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Style mode: prompt'
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'Use a release: prefix'
}

@test "--style prompt fails without --prompt" {
  local repo="$TEST_ROOT/prompt-style-missing"
  init_git_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'release: missing'

  run run_in_repo "$repo" --agent codex --vcs git --style prompt

  assert_failure
  assert_contains "$output" '--style prompt requires --prompt.'
}

@test "literal placeholder tokens in prompt inputs remain verbatim" {
  local repo="$TEST_ROOT/literal-placeholders"
  local prompt_text
  init_git_repo "$repo"
  printf 'history token\n' >"$repo/file.txt"
  git -C "$repo" commit -am 'docs: mention {{DIFF}} literally' -q
  printf 'staged change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'feat: literal placeholders'

  run run_in_repo "$repo" --agent codex --vcs git --prompt 'Say {{DIFF}} literally'

  assert_success
  prompt_text="$(cat "$AGENT_STDIN_FILE")"
  assert_contains "$prompt_text" 'Say {{DIFF}} literally'
  assert_contains "$prompt_text" 'docs: mention {{DIFF}} literally'
  assert_contains "$prompt_text" 'staged change'
}

@test "template override replaces the default template" {
  local repo="$TEST_ROOT/template-override"
  local template_file="$TEST_ROOT/custom-template.txt"
  init_git_repo "$repo"
  cat >"$template_file" <<'EOF'
CUSTOM TEMPLATE
VCS={{VCS}}
STYLE={{STYLE_MODE}}
GUIDANCE={{USER_GUIDANCE}}
HISTORY={{RECENT_SUBJECTS}}
PATCH={{DIFF}}
EOF
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'feat: custom template'

  run run_in_repo "$repo" --agent codex --vcs git --template-file "$template_file" --prompt 'custom guidance'

  assert_success
  [[ "$(cat "$AGENT_STDIN_FILE")" == CUSTOM\ TEMPLATE* ]]
  assert_contains "$(cat "$AGENT_STDIN_FILE")" 'GUIDANCE=custom guidance'
  if [[ "$(cat "$AGENT_STDIN_FILE")" == *'Output contract:'* ]]; then
    printf 'default template leaked into override prompt\n' >&2
    return 1
  fi
}

@test "each agent preset resolves to the expected default command" {
  local repo="$TEST_ROOT/agent-presets"
  init_git_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt

  set_agent_output 'feat: codex'
  run run_in_repo "$repo" --agent codex --vcs git
  assert_success
  [[ "$(cat "$AGENT_NAME_FILE")" == 'codex' ]]
  load_agent_args
  [[ "${agent_args[*]}" == 'exec --dangerously-bypass-approvals-and-sandbox -' ]]
  [[ -n "$(cat "$AGENT_STDIN_FILE")" ]]

  git -C "$repo" reset --soft HEAD~1 >/dev/null
  printf 'change again\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt

  set_agent_output 'feat: claude'
  run run_in_repo "$repo" --agent claude --vcs git
  assert_success
  [[ "$(cat "$AGENT_NAME_FILE")" == 'claude' ]]
  load_agent_args
  [[ "${agent_args[0]}" == '-p' ]]
  [[ "${agent_args[1]}" == '--permission-mode' ]]
  [[ "${agent_args[2]}" == 'bypassPermissions' ]]
  [[ -n "${agent_args[3]}" ]]
  [[ -z "$(cat "$AGENT_STDIN_FILE")" ]]

  git -C "$repo" reset --soft HEAD~1 >/dev/null
  printf 'change once more\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt

  set_agent_output 'feat: cursor'
  run run_in_repo "$repo" --agent cursor-agent --vcs git
  assert_success
  [[ "$(cat "$AGENT_NAME_FILE")" == 'cursor-agent' ]]
  load_agent_args
  [[ "${agent_args[0]}" == '-p' ]]
  [[ "${agent_args[1]}" == '--yolo' ]]
  [[ "${agent_args[2]}" == '--trust' ]]
  [[ "${agent_args[3]}" == '--approve-mcps' ]]
  [[ -n "${agent_args[4]}" ]]
  [[ -z "$(cat "$AGENT_STDIN_FILE")" ]]
}

@test "repeated --agent-arg values are appended after preset defaults" {
  local repo="$TEST_ROOT/agent-arg"
  init_git_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'feat: appended args'

  run run_in_repo "$repo" --agent claude --vcs git --agent-arg --model --agent-arg sonnet

  assert_success
  load_agent_args
  [[ "${agent_args[0]}" == '-p' ]]
  [[ "${agent_args[1]}" == '--permission-mode' ]]
  [[ "${agent_args[2]}" == 'bypassPermissions' ]]
  [[ "${agent_args[3]}" == '--model' ]]
  [[ "${agent_args[4]}" == 'sonnet' ]]
}

@test "wrapper performs the commit itself from agent output" {
  local repo="$TEST_ROOT/wrapper-commits"
  init_git_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output 'feat: wrapper owns commit'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_success
  [[ "$(git -C "$repo" log -1 --format=%s)" == 'feat: wrapper owns commit' ]]
}

@test "multiline commit messages are preserved" {
  local repo="$TEST_ROOT/multiline"
  init_git_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output $'feat: multiline\n\nBody line one\nBody line two'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_success
  [[ "$(git -C "$repo" log -1 --format=%B)" == $'feat: multiline\n\nBody line one\nBody line two' ]]
}

@test "fenced agent output with surrounding blank lines is normalized before commit" {
  local repo="$TEST_ROOT/fenced-output"
  init_git_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output $'\n```markdown\nfeat: fenced subject\n\nBody line one\nBody line two\n```\n'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_success
  [[ "$(git -C "$repo" log -1 --format=%B)" == $'feat: fenced subject\n\nBody line one\nBody line two' ]]
}

@test "fenced agent output ignores trailing prose after the closing fence" {
  local repo="$TEST_ROOT/fenced-output-trailing-prose"
  init_git_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  git -C "$repo" add file.txt
  set_agent_output $'```markdown\nfeat: fenced subject\n\nBody line one\n```\nTrailing explanation\n'

  run run_in_repo "$repo" --agent codex --vcs git

  assert_success
  [[ "$(git -C "$repo" log -1 --format=%B)" == $'feat: fenced subject\n\nBody line one' ]]
}

@test "jj mode preserves normalized multiline commit messages" {
  local repo="$TEST_ROOT/jj-fenced-output"
  init_jj_repo "$repo"
  printf 'change\n' >>"$repo/file.txt"
  set_agent_output $'\n```markdown\nfeat: jj fenced subject\n\nBody line one\nBody line two\n```\n'

  run run_in_repo "$repo" --agent codex --vcs jj

  assert_success
  [[ "$(jj -R "$repo" log -r @- -n 1 --no-graph -T 'description')" == $'feat: jj fenced subject\n\nBody line one\nBody line two' ]]
}
