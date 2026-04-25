---
name: talk
description: Coordinate with another AI agent through tmux using a small XML message protocol. Use when Codex needs to send work to an agent in another tmux pane, request help from a peer agent, or respond to a structured tmux protocol message containing tmuxp-requester, tmuxp-replier, tmuxp-name, tmuxp-request, tmuxp-request-id, tmuxp-reply-id, tmuxp-reply, tmuxp-error, tmuxp-next-request-id, or tmuxp-next-request tags.
---

# Talk

## Overview

Use this skill to communicate with another agent that is already running in a tmux pane. Send requests and replies as plain XML fragments so both sides can reliably identify the requester, identify the replier, correlate replies, distinguish successful answers from errors, and optionally continue into another request-reply turn.

For the exact wire format, required tags, escaping rules, and examples, read `references/protocol.md`.

## Workflow

1. Identify the target tmux pane.
   - Prefer a user-provided pane target when available.
   - If the user gives a name such as `codex-review` instead of a pane id, run `<this-skill-directory>/scripts/tmuxp-info <name>` and use its `target: <pane-id>` output.
   - If `tmuxp-info` reports multiple matches, choose an explicit pane id from its candidate rows before sending.
   - This skill does not create windows, launch agents, or manage agent lifecycle.
2. Put the pane that should receive the response in `<tmuxp-requester>`.
   - `<tmuxp-requester>` must be a tmux target that another agent can pass to `tmux send-keys -t`, such as `%12`, `agent-session:1.2`, or `:1.2`.
   - Put a human-readable label in optional `<tmuxp-name>` when useful, such as `codex-main` or `reviewer`.
3. Generate a unique request id for each request that expects a reply.
   - Use compact ids such as `req-20260426-153012-a`.
   - Keep the same request id when replying and add a fresh reply id.
4. Send one XML protocol fragment to the target pane, preferably with the helper at `<this-skill-directory>/scripts/tmuxp`.
   - Do not wrap the protocol in Markdown fences.
   - Keep prose inside the XML payload, not outside it.
   - For multi-line requests, encode line breaks inside `<tmuxp-request>` instead of sending physical newline characters to the target pane.
5. Stop after sending.
   - Do not run `tmux capture-pane`, `sleep`, loops, repeated `tmuxp-info`, or any polling commands to wait for a reply.
   - Do not inspect the target pane to read the answer; the reply must arrive as a tmuxp protocol message in your requester pane.
   - The receiving agent is responsible for sending a reply back to the tmux target in `<tmuxp-requester>`.
6. When receiving a tmuxp request, do the requested work if it is in scope, then send a tmuxp reply or error to the requester pane.
7. When receiving a tmuxp reply or error with `<tmuxp-next-request-id>` and `<tmuxp-next-request>`, treat it as a dialogue turn.
   - First process the reply or error as the answer to your original request.
   - Then answer `<tmuxp-next-request>` as a new request from the replier, using `<tmuxp-next-request-id>` as the request id to echo in your reply.

## Helper

Use the included read-only info helper before sending when you need to resolve a pane or window name:

```bash
<this-skill-directory>/scripts/tmuxp-info codex-review
```

Use the included send-only helper for normal requests and replies. It sends to an existing pane only.

```bash
<this-skill-directory>/scripts/tmuxp request --to <target-pane> --name codex-main -- "Summarize the failing test output."
```

For longer messages, use stdin:

```bash
printf '%s\n' "Summarize the failing test output." | <this-skill-directory>/scripts/tmuxp request --to <target-pane> --name codex-main --stdin
```

Replies and errors include both requester and replier panes:

```bash
<this-skill-directory>/scripts/tmuxp reply --to <requester-pane> --request-id <request-id> --name reviewer -- "No issues found."
<this-skill-directory>/scripts/tmuxp error --to <requester-pane> --request-id <request-id> --name reviewer -- "I cannot inspect the target pane."
```

To continue the dialogue from a reply, attach a next request:

```bash
<this-skill-directory>/scripts/tmuxp reply --to <requester-pane> --request-id <request-id> --name reviewer --next-request "Can you run the focused test now?" -- "I updated the parser."
```

Do not run a bare `scripts/tmuxp` or `scripts/tmuxp-info` from the repository or shell cwd. Resolve helpers relative to this skill directory, then invoke those paths.

The helper resolves the current pane for `auto` requester or replier values during real sends, generates ids when requested, escapes payloads safely into a single-line XML fragment, pastes the fragment through a temporary tmux buffer that is deleted after paste, waits briefly, and submits it with `tmux send-keys Enter`. With `--dry-run`, unresolved `auto` pane values print as the literal placeholder `auto`; pass explicit pane values when the dry-run output must be a sendable protocol fragment.

The info helper prints the current pane and available panes. With a query, it prints `target: <pane-id>` only when the query resolves to exactly one pane; if the query is missing or ambiguous, choose an explicit pane id before calling `tmuxp`.

## Receiving Requests

When a tmuxp request arrives in your pane:

- Parse the tmuxp tags before acting.
- Treat `<tmuxp-request>` content as the task payload.
- Do not invent missing context; ask back with a tmuxp reply if the request is ambiguous.
- Include the original `<tmuxp-request-id>` in every reply or error.
- Include a new `<tmuxp-reply-id>` in every reply or error.
- If a reply or error includes `<tmuxp-next-request-id>` and `<tmuxp-next-request>`, process those as a new request from the replier after processing the reply.
- Keep final replies concise and actionable.

## Reference

Read `references/protocol.md` when you need to construct, parse, validate, or troubleshoot tmuxp messages.
