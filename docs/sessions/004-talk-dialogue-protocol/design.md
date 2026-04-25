# Talk Dialogue Protocol Design

## Goal

Extend the `talk` skill so a reply can optionally carry the next request in the same tmuxp XML fragment. This makes a request-reply exchange usable as a dialogue: the original replier can answer the current request and immediately ask the next question, with roles flipped for the next turn.

## Protocol

Replies and errors keep the existing correlation tags unchanged:

- `<tmuxp-request-id>` remains the id of the original request being answered.
- `<tmuxp-reply-id>` remains the id of the current reply or error.
- `<tmuxp-requester>` remains the pane that should receive this reply.
- `<tmuxp-replier>` remains the pane sending this reply.

When the reply also starts a next turn, it adds two optional tags:

- `<tmuxp-next-request-id>`: fresh request id for the next turn.
- `<tmuxp-next-request>`: request payload for the next turn.

The next-turn tags are only valid as a pair. They avoid duplicating `<tmuxp-request-id>`, which already has a precise meaning in replies.

## Helper

Add continuation options to `tmuxp reply` and `tmuxp error`:

- `--next-request <message>` adds `<tmuxp-next-request>` with a fresh generated next request id by default.
- `--next-request-id <id|auto>` controls the id written to `<tmuxp-next-request-id>`.

The normal reply or error payload continues to come from the trailing message or `--stdin`. The helper should reject `--next-request-id` without `--next-request`, and reject `--next-request` on the `request` subcommand.

## Data Flow

The sender builds one single-line XML fragment. A plain reply is unchanged. A dialogue reply appends next-turn tags after the reply or error payload:

```xml
<tmuxp-requester>%12</tmuxp-requester><tmuxp-replier>%15</tmuxp-replier><tmuxp-request-id>req-a</tmuxp-request-id><tmuxp-reply-id>rep-a</tmuxp-reply-id><tmuxp-reply>Done.</tmuxp-reply><tmuxp-next-request-id>req-b</tmuxp-next-request-id><tmuxp-next-request>Can you verify the tests?</tmuxp-next-request>
```

On receipt, the original requester treats the reply or error as the answer to the original request. If next-turn tags are present, it treats `<tmuxp-next-request>` as a new request from the original replier and answers it with a new reply fragment that echoes `<tmuxp-next-request-id>` as that reply's `<tmuxp-request-id>`.

## Error Handling

Existing XML escaping rules apply to the next request payload. The helper exits non-zero when only one of the next-turn tags would be emitted, when the next request payload is empty, or when next-turn options are passed to `tmuxp request`.

## Testing

Use dry-run tests to verify:

- Existing request, reply, and error output remains unchanged without continuation options.
- A reply can include `<tmuxp-next-request-id>` and `<tmuxp-next-request>`.
- An error can include next-turn tags.
- Next request text is XML-escaped.
- Invalid option combinations fail with clear errors.
