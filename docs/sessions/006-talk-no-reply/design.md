# Talk No-Reply Requests

## Context

The talk protocol currently models every request as synchronized: a sender includes `<tmuxp-requester>` and `<tmuxp-request-id>`, then the receiver must answer with a reply or error. Some coordination messages are notifications where a reply adds no useful information, such as status updates, cancellation notices, or one-way ownership announcements.

## Decision

Add explicit asynchronous requests with a `<tmuxp-no-reply>true</tmuxp-no-reply>` marker. The payload stays in `<tmuxp-request>` so receivers can parse one request payload shape. A no-reply request still carries `<tmuxp-requester>` and `<tmuxp-request-id>` as origin and correlation metadata; the marker only changes the response expectation.

The helper exposes this as:

```bash
tmuxp request --no-reply --to <pane> [--name <name>] [--stdin] [--dry-run] -- <message>
```

`--no-reply` is also valid on `reply` and `error` when paired with `--next-request`. In that form it marks the attached next request as asynchronous:

```bash
tmuxp reply --to <pane> --request-id <id> --next-request "Status update" --no-reply -- "Done."
```

A no-reply next request includes `<tmuxp-next-request-id>`, `<tmuxp-no-reply>true</tmuxp-no-reply>`, and `<tmuxp-next-request>`. The next request id remains useful for logs, references, and cross-pane coordination even when no answer is expected.

`--no-reply` on `request` can be combined with `--requester` and `--request-id`, and defaults those values the same way as synchronized requests. `--no-reply` on `reply` or `error` rejects missing `--next-request` because there would be no next request to mark.

## Sender Rule

The sender chooses synchronized or no-reply based on whether it needs an answer. Use normal request/reply when the sender needs a result, confirmation, error report, decision, review, generated artifact, or continued dialogue. Use no-reply only for fire-and-forget coordination where a reply would add no value.

## Receiver Rule

When `<tmuxp-no-reply>true</tmuxp-no-reply>` is present on a top-level request, the receiver processes `<tmuxp-request>` as the task payload and must not send a tmuxp reply or error. When the marker is present with `<tmuxp-next-request>`, the original requester processes the reply or error first, then treats `<tmuxp-next-request>` as a no-reply request from the original replier.

When the marker is absent, the existing synchronized request contract remains unchanged: the receiver sends a reply or error to `<tmuxp-requester>` using the original `<tmuxp-request-id>`, and synchronized next requests include `<tmuxp-next-request-id>`.

## Testing

Add focused Bats coverage for:

- no-reply request XML construction
- no-reply stdin payload escaping
- no-reply next request XML construction on reply/error
- rejection of `--no-reply` on reply/error without `--next-request`
