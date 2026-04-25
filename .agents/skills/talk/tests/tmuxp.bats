#!/usr/bin/env bats

setup() {
  SKILL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT_PATH="$SKILL_ROOT/scripts/tmuxp"
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

@test "prints help" {
  run "$SCRIPT_PATH" --help

  assert_success
  assert_contains "$output" 'tmuxp request --to <pane>'
  assert_contains "$output" 'tmuxp reply   --to <pane> --request-id <id>'
  assert_contains "$output" 'tmuxp error   --to <pane> --request-id <id>'
}

@test "request dry-run builds a protocol fragment with explicit ids" {
  run "$SCRIPT_PATH" request \
    --dry-run \
    --to %15 \
    --requester %12 \
    --request-id req-test \
    --name codex-main \
    -- "Review the diff"

  assert_success
  [[ "$output" == '<tmuxp-requester>%12</tmuxp-requester><tmuxp-name>codex-main</tmuxp-name><tmuxp-request-id>req-test</tmuxp-request-id><tmuxp-request>Review the diff</tmuxp-request>' ]]
}

@test "reply dry-run builds a successful reply fragment" {
  run "$SCRIPT_PATH" reply \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    --replier %15 \
    --name reviewer \
    -- "No issues found."

  assert_success
  [[ "$output" == '<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-name>reviewer</tmuxp-name><tmuxp-request-id>req-test</tmuxp-request-id><tmuxp-reply-id>rep-test</tmuxp-reply-id><tmuxp-reply>No issues found.</tmuxp-reply>' ]]
}

@test "error dry-run builds an error reply fragment" {
  run "$SCRIPT_PATH" error \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    --replier %15 \
    -- "Cannot inspect the target pane."

  assert_success
  [[ "$output" == '<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-request-id>req-test</tmuxp-request-id><tmuxp-reply-id>rep-test</tmuxp-reply-id><tmuxp-error>Cannot inspect the target pane.</tmuxp-error>' ]]
}

@test "dry-run escapes XML metacharacters in payloads" {
  run "$SCRIPT_PATH" request \
    --dry-run \
    --to %15 \
    --requester %12 \
    --request-id req-test \
    -- 'Use A&B < C > D'

  assert_success
  assert_contains "$output" '<tmuxp-request>Use A&amp;B &lt; C &gt; D</tmuxp-request>'
}

@test "stdin payload encodes newlines as XML character references" {
  run bash -c 'printf "line one\nline two\n" | "$1" request --dry-run --to %15 --requester %12 --request-id req-test --stdin' _ "$SCRIPT_PATH"

  assert_success
  assert_contains "$output" '<tmuxp-request>line one&#10;line two&#10;</tmuxp-request>'
}

@test "rejects stdin combined with trailing message text" {
  run "$SCRIPT_PATH" request \
    --dry-run \
    --to %15 \
    --requester %12 \
    --request-id req-test \
    --stdin \
    -- "message"

  assert_failure
  assert_contains "$output" 'tmuxp: use either --stdin or trailing message text, not both'
}

@test "missing message fails with validation error" {
  run "$SCRIPT_PATH" request \
    --dry-run \
    --to %15 \
    --requester %12 \
    --request-id req-test

  assert_failure
  assert_contains "$output" 'tmuxp: message must not be empty'
}

@test "default request dry-run does not require an accessible tmux client" {
  run env PATH=/usr/bin:/bin "$SCRIPT_PATH" request \
    --dry-run \
    --to %15 \
    --request-id req-test \
    -- "Review the diff"

  assert_success
  assert_contains "$output" '<tmuxp-requester>auto</tmuxp-requester>'
  assert_contains "$output" '<tmuxp-request>Review the diff</tmuxp-request>'
}

@test "default reply dry-run does not require an accessible tmux client" {
  run env PATH=/usr/bin:/bin "$SCRIPT_PATH" reply \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    -- "Done"

  assert_success
  assert_contains "$output" '<tmuxp-requester>%12</tmuxp-requester>'
  assert_contains "$output" '<tmuxp-replier>auto</tmuxp-replier>'
  assert_contains "$output" '<tmuxp-reply>Done</tmuxp-reply>'
}
