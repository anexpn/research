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
  assert_contains "$output" '--no-reply'
  assert_contains "$output" '--next-request <message>'
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

@test "no-reply request dry-run builds an async protocol fragment" {
  run "$SCRIPT_PATH" request \
    --dry-run \
    --to %15 \
    --no-reply \
    --requester %12 \
    --request-id req-test \
    --name codex-main \
    -- "I started the test run."

  assert_success
  [[ "$output" == '<tmuxp-requester>%12</tmuxp-requester><tmuxp-name>codex-main</tmuxp-name><tmuxp-request-id>req-test</tmuxp-request-id><tmuxp-no-reply>true</tmuxp-no-reply><tmuxp-request>I started the test run.</tmuxp-request>' ]]
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

@test "reply dry-run can attach a next request for dialogue" {
  run "$SCRIPT_PATH" reply \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    --replier %15 \
    --next-request-id req-next \
    --next-request "Can you run the focused test now?" \
    -- "I updated the parser."

  assert_success
  [[ "$output" == '<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-request-id>req-test</tmuxp-request-id><tmuxp-reply-id>rep-test</tmuxp-reply-id><tmuxp-reply>I updated the parser.</tmuxp-reply><tmuxp-next-request-id>req-next</tmuxp-next-request-id><tmuxp-next-request>Can you run the focused test now?</tmuxp-next-request>' ]]
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

@test "error dry-run can attach a next request for dialogue" {
  run "$SCRIPT_PATH" error \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    --replier %15 \
    --next-request-id req-next \
    --next-request "Send me the failing command." \
    -- "Cannot inspect the target pane."

  assert_success
  [[ "$output" == '<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-request-id>req-test</tmuxp-request-id><tmuxp-reply-id>rep-test</tmuxp-reply-id><tmuxp-error>Cannot inspect the target pane.</tmuxp-error><tmuxp-next-request-id>req-next</tmuxp-next-request-id><tmuxp-next-request>Send me the failing command.</tmuxp-next-request>' ]]
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

@test "dry-run escapes XML metacharacters in next request payloads" {
  run "$SCRIPT_PATH" reply \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    --replier %15 \
    --next-request-id req-next \
    --next-request 'Check A&B < C > D' \
    -- "Done"

  assert_success
  assert_contains "$output" '<tmuxp-next-request>Check A&amp;B &lt; C &gt; D</tmuxp-next-request>'
}

@test "stdin payload encodes newlines as XML character references" {
  run bash -c 'printf "line one\nline two\n" | "$1" request --dry-run --to %15 --requester %12 --request-id req-test --stdin' _ "$SCRIPT_PATH"

  assert_success
  assert_contains "$output" '<tmuxp-request>line one&#10;line two&#10;</tmuxp-request>'
}

@test "no-reply stdin payload encodes newlines as XML character references" {
  run bash -c 'printf "line one\nline two\n" | "$1" request --dry-run --to %15 --requester %12 --request-id req-test --no-reply --stdin' _ "$SCRIPT_PATH"

  assert_success
  [[ "$output" == '<tmuxp-requester>%12</tmuxp-requester><tmuxp-request-id>req-test</tmuxp-request-id><tmuxp-no-reply>true</tmuxp-no-reply><tmuxp-request>line one&#10;line two&#10;</tmuxp-request>' ]]
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

@test "next request id without next request fails" {
  run "$SCRIPT_PATH" reply \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    --next-request-id req-next \
    -- "Done"

  assert_failure
  assert_contains "$output" 'tmuxp: use --next-request-id only with --next-request'
}

@test "empty next request fails" {
  run "$SCRIPT_PATH" reply \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    --next-request "" \
    -- "Done"

  assert_failure
  assert_contains "$output" 'tmuxp: next request must not be empty'
}

@test "request rejects next request options" {
  run "$SCRIPT_PATH" request \
    --dry-run \
    --to %15 \
    --requester %12 \
    --request-id req-test \
    --next-request "Follow up" \
    -- "Review the diff"

  assert_failure
  assert_contains "$output" 'tmuxp: unrecognized argument: --next-request'
}

@test "reply dry-run can attach a no-reply next request" {
  run "$SCRIPT_PATH" reply \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    --replier %15 \
    --next-request-id req-next \
    --next-request "I started the focused test run." \
    --no-reply \
    -- "Done"

  assert_success
  [[ "$output" == '<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-request-id>req-test</tmuxp-request-id><tmuxp-reply-id>rep-test</tmuxp-reply-id><tmuxp-reply>Done</tmuxp-reply><tmuxp-next-request-id>req-next</tmuxp-next-request-id><tmuxp-no-reply>true</tmuxp-no-reply><tmuxp-next-request>I started the focused test run.</tmuxp-next-request>' ]]
}

@test "error dry-run can attach a no-reply next request" {
  run "$SCRIPT_PATH" error \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --reply-id rep-test \
    --replier %15 \
    --next-request-id req-next \
    --next-request "I am cancelling the duplicate investigation." \
    --no-reply \
    -- "Cannot inspect the target pane."

  assert_success
  [[ "$output" == '<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-request-id>req-test</tmuxp-request-id><tmuxp-reply-id>rep-test</tmuxp-reply-id><tmuxp-error>Cannot inspect the target pane.</tmuxp-error><tmuxp-next-request-id>req-next</tmuxp-next-request-id><tmuxp-no-reply>true</tmuxp-no-reply><tmuxp-next-request>I am cancelling the duplicate investigation.</tmuxp-next-request>' ]]
}

@test "reply rejects no-reply without next request" {
  run "$SCRIPT_PATH" reply \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --no-reply \
    -- "Done"

  assert_failure
  assert_contains "$output" 'tmuxp: use --no-reply only with --next-request on reply or error'
}

@test "reply accepts no-reply with next request id" {
  run "$SCRIPT_PATH" reply \
    --dry-run \
    --to %12 \
    --request-id req-test \
    --next-request "Follow up" \
    --next-request-id req-next \
    --no-reply \
    -- "Done"

  assert_success
  assert_contains "$output" '<tmuxp-next-request-id>req-next</tmuxp-next-request-id><tmuxp-no-reply>true</tmuxp-no-reply><tmuxp-next-request>Follow up</tmuxp-next-request>'
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
