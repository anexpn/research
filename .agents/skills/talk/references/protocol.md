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

Optional dialogue continuation tags for a reply or error:

```xml
<tmuxp-next-request-id>next-request-id</tmuxp-next-request-id><tmuxp-next-request>next request payload</tmuxp-next-request>
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
- `<tmuxp-next-request-id>`: Fresh request correlation id for a next dialogue turn attached to a reply or error. Do not use `<tmuxp-request-id>` for this; in replies and errors, that tag already identifies the request being answered.
- `<tmuxp-next-request>`: New work request attached to a reply or error. The original replier becomes the requester for this next turn, and the original requester becomes the replier.

`<tmuxp-next-request-id>` and `<tmuxp-next-request>` are only valid as a pair.

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
<talk-skill-directory>/scripts/tmuxp request --to %15 --name codex-main -- "Summarize the failing test output."
```

Use the read-only info helper before sending when a user gives a pane or window name instead of an exact pane id:

```bash
<talk-skill-directory>/scripts/tmuxp-info codex-review
```

The info helper prints the current pane and available panes. With a query, it prints `target: <pane-id>` only when the query resolves to exactly one pane; if the query is missing or ambiguous, choose an explicit pane id before calling `tmuxp`.

The send helper sends one single-line fragment to an existing pane only. It does not create windows, launch Codex, inspect windows, or manage agent lifecycle.

For long payloads, read from stdin:

```bash
printf '%s\n' "Summarize the failing test output." | <talk-skill-directory>/scripts/tmuxp request --to %15 --name codex-main --stdin
```

Reply:

```bash
<talk-skill-directory>/scripts/tmuxp reply --to %12 --request-id req-20260426-153012-a --name reviewer -- "No issues found."
```

Reply with next request:

```bash
<talk-skill-directory>/scripts/tmuxp reply --to %12 --request-id req-20260426-153012-a --name reviewer --next-request "Can you run the focused test now?" -- "I updated the parser."
```

Error:

```bash
<talk-skill-directory>/scripts/tmuxp error --to %12 --request-id req-20260426-153012-a --name reviewer -- "I cannot inspect the failure because this pane has no test output."
```

Use `--dry-run` to print the XML fragment without sending it. Dry-run output keeps unresolved `auto` requester or replier pane values as the literal placeholder `auto` so XML construction can be checked without a live tmux client; pass explicit `--requester` and `--replier` values when dry-run output must be sendable as-is. Resolve helpers relative to the talk skill directory; do not assume `scripts/tmuxp` or `scripts/tmuxp-info` exists under the current working directory.

## Request Construction Checklist

Before sending a request:

1. Confirm the target pane is the intended agent.
   - If the user gave a name such as `codex-review`, run `tmuxp-info <name>` and use its `target: <pane-id>` output.
   - If `tmuxp-info` reports multiple matches, choose an explicit pane id from its candidate rows before sending.
2. Put your own replyable tmux target in `<tmuxp-requester>`.
3. Generate a fresh request id.
4. Put all task instructions inside `<tmuxp-request>`.
5. Put any human-readable agent name in optional `<tmuxp-name>`.
6. Avoid Markdown fences around the protocol fragment.
7. Send exactly one single-line protocol fragment, then submit it with Enter.
8. After sending, do not run `tmux capture-pane`, `sleep`, loops, repeated `tmuxp-info`, or any polling commands to wait for a reply.
9. Do not inspect the target pane to read the answer; the reply must arrive as a tmuxp protocol message in your requester pane.

## Reply Construction Checklist

Before sending a reply or error:

1. Include the original requester target in `<tmuxp-requester>`.
2. Include your own replyable tmux target in `<tmuxp-replier>`.
3. Copy the original request id exactly.
4. Generate a fresh reply id.
5. Use exactly one of `<tmuxp-reply>` or `<tmuxp-error>`.
6. Add `<tmuxp-name>` only when a human-readable agent label is useful.
7. To continue the dialogue, add both `<tmuxp-next-request-id>` and `<tmuxp-next-request>`.
8. Keep the payload specific enough for the requester to continue without rereading the target pane.

## Dialogue Handling Checklist

When receiving a reply or error with next-turn tags:

1. Process `<tmuxp-reply>` or `<tmuxp-error>` as the answer to your original request.
2. Treat `<tmuxp-next-request>` as a new request from the original replier.
3. Echo `<tmuxp-next-request-id>` as `<tmuxp-request-id>` in your reply or error to that new request.
4. Send the answer to the pane in `<tmuxp-replier>` because that pane becomes the requester for the next turn.

## Examples

Request:

```xml
<tmuxp-requester>%12</tmuxp-requester><tmuxp-name>codex-main</tmuxp-name><tmuxp-request-id>req-20260426-153012-a</tmuxp-request-id><tmuxp-request>Please inspect the test failure visible in your pane and report the likely cause plus the file to edit.</tmuxp-request>
```

Reply:

```xml
<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-name>reviewer</tmuxp-name><tmuxp-request-id>req-20260426-153012-a</tmuxp-request-id><tmuxp-reply-id>rep-20260426-153255-b</tmuxp-reply-id><tmuxp-reply>The failure is an assertion mismatch in tests/test_parser.py. The parser now preserves trailing whitespace, but the expected fixture still trims it.</tmuxp-reply>
```

Reply with next request:

```xml
<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-name>reviewer</tmuxp-name><tmuxp-request-id>req-20260426-153012-a</tmuxp-request-id><tmuxp-reply-id>rep-20260426-153255-d</tmuxp-reply-id><tmuxp-reply>I updated the parser.</tmuxp-reply><tmuxp-next-request-id>req-20260426-153300-e</tmuxp-next-request-id><tmuxp-next-request>Can you run the focused test now?</tmuxp-next-request>
```

Error:

```xml
<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-name>reviewer</tmuxp-name><tmuxp-request-id>req-20260426-153012-a</tmuxp-request-id><tmuxp-reply-id>rep-20260426-153255-c</tmuxp-reply-id><tmuxp-error>I cannot inspect the failure because this pane has no test output. Send the failing command or target pane.</tmuxp-error>
```
