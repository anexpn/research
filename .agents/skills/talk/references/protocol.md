# Tmuxp XML Protocol

Use this reference as the wire contract for agent-to-agent messages sent through tmux.

## Message Model

The protocol uses XML fragments, not a single document root, because fragments are easy to paste into terminal prompts. Send only the protocol fragment to the other agent unless the user explicitly asks for surrounding explanation.

Required tags for a request:

```xml
<tmuxp-requester>requester-tmux-target</tmuxp-requester><tmuxp-request-id>request-id</tmuxp-request-id><tmuxp-request>task payload</tmuxp-request>
```

Optional agent display name:

```xml
<tmuxp-name>agent-display-name</tmuxp-name>
```

Required tags for a successful reply:

```xml
<tmuxp-requester>requester-tmux-target</tmuxp-requester><tmuxp-replier>replier-tmux-target</tmuxp-replier><tmuxp-request-id>original-request-id</tmuxp-request-id><tmuxp-reply-id>reply-id</tmuxp-reply-id><tmuxp-reply>reply payload</tmuxp-reply>
```

Required tags for a failed or refused request:

```xml
<tmuxp-requester>requester-tmux-target</tmuxp-requester><tmuxp-replier>replier-tmux-target</tmuxp-replier><tmuxp-request-id>original-request-id</tmuxp-request-id><tmuxp-reply-id>reply-id</tmuxp-reply-id><tmuxp-error>error payload</tmuxp-error>
```

## Tag Semantics

- `<tmuxp-requester>`: Tmux target for the pane that requested the work and should receive the response. Use a value the receiver can pass to `tmux send-keys -t`, such as `%12`, `agent-session:1.2`, or `:1.2`. Helper dry-runs may print the placeholder `auto` when the caller does not provide an explicit requester; do not send that placeholder as a real protocol target.
- `<tmuxp-replier>`: Tmux target for the pane that completed or refused the work. Helper dry-runs may print the placeholder `auto` when the caller does not provide an explicit replier.
- `<tmuxp-name>`: Optional human-readable label for the agent that sends the current fragment. Use this for names, roles, or aliases such as `codex-main` or `reviewer`; do not put names in tmux target tags.
- `<tmuxp-request-id>`: Request correlation id. Generate it on request. Echo it unchanged in replies and errors.
- `<tmuxp-reply-id>`: Reply correlation id. Generate it on each reply or error.
- `<tmuxp-request>`: Work request for the receiving agent. Include enough context, constraints, expected output shape, and any file paths or pane targets needed.
- `<tmuxp-reply>`: Successful answer. Include the completed work, result, or concise handoff.
- `<tmuxp-error>`: Failure answer. Include what prevented completion and the smallest useful next step.

## Escaping Rules

Escape XML metacharacters inside tag content:

- `&` as `&amp;`
- `<` as `&lt;`
- `>` as `&gt;` when it could be mistaken for markup

Prefer plain text payloads. For terminal transport, helpers should send the whole protocol fragment as a single physical line. Escape XML-like content and encode payload line breaks as `&#10;` so the final `Enter` is the only terminal newline.

Do not nest tmuxp protocol fragments inside payloads unless you are explicitly discussing the protocol itself.

## Helper

Prefer the included send-only helper for normal use:

```bash
/Users/jun/code/mine/research/.agents/skills/talk/scripts/tmuxp request --to %15 --name codex-main -- "Summarize the failing test output."
```

The helper sends one single-line fragment to an existing pane only. It does not create windows, launch Codex, inspect windows, or manage agent lifecycle.

For long payloads, read from stdin:

```bash
/Users/jun/code/mine/research/.agents/skills/talk/scripts/tmuxp request --to %15 --name codex-main --stdin
```

Reply:

```bash
/Users/jun/code/mine/research/.agents/skills/talk/scripts/tmuxp reply --to %12 --request-id req-20260426-153012-a --name reviewer -- "No issues found."
```

Error:

```bash
/Users/jun/code/mine/research/.agents/skills/talk/scripts/tmuxp error --to %12 --request-id req-20260426-153012-a --name reviewer -- "I cannot inspect the failure because this pane has no test output."
```

Use `--dry-run` to print the XML fragment without sending it. Dry-run output keeps unresolved `auto` requester or replier pane values as the literal placeholder `auto` so XML construction can be checked without a live tmux client; pass explicit `--requester` and `--replier` values when dry-run output must be sendable as-is. Resolve this helper relative to the talk skill directory; do not assume `scripts/tmuxp` exists under the current working directory.

## Request Construction Checklist

Before sending a request:

1. Confirm the target pane is the intended agent.
2. Put your own replyable tmux target in `<tmuxp-requester>`.
3. Generate a fresh request id.
4. Put all task instructions inside `<tmuxp-request>`.
5. Put any human-readable agent name in optional `<tmuxp-name>`.
6. Avoid Markdown fences around the protocol fragment.
7. Send exactly one single-line protocol fragment, then submit it with Enter.
8. Do not run extra `tmux capture-pane`, `sleep`, or polling commands. The receiver will send the reply itself.

## Reply Construction Checklist

Before sending a reply or error:

1. Include the original requester target in `<tmuxp-requester>`.
2. Include your own replyable tmux target in `<tmuxp-replier>`.
3. Copy the original request id exactly.
4. Generate a fresh reply id.
5. Use exactly one of `<tmuxp-reply>` or `<tmuxp-error>`.
6. Add `<tmuxp-name>` only when a human-readable agent label is useful.
7. Keep the payload specific enough for the requester to continue without rereading the target pane.

## Examples

Request:

```xml
<tmuxp-requester>%12</tmuxp-requester><tmuxp-name>codex-main</tmuxp-name><tmuxp-request-id>req-20260426-153012-a</tmuxp-request-id><tmuxp-request>Please inspect the test failure visible in your pane and report the likely cause plus the file to edit.</tmuxp-request>
```

Reply:

```xml
<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-name>reviewer</tmuxp-name><tmuxp-request-id>req-20260426-153012-a</tmuxp-request-id><tmuxp-reply-id>rep-20260426-153255-b</tmuxp-reply-id><tmuxp-reply>The failure is an assertion mismatch in tests/test_parser.py. The parser now preserves trailing whitespace, but the expected fixture still trims it.</tmuxp-reply>
```

Error:

```xml
<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-name>reviewer</tmuxp-name><tmuxp-request-id>req-20260426-153012-a</tmuxp-request-id><tmuxp-reply-id>rep-20260426-153255-c</tmuxp-reply-id><tmuxp-error>I cannot inspect the failure because this pane has no test output. Send the failing command or target pane.</tmuxp-error>
```
