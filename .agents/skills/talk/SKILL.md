---
name: talk
description: Coordinate with another AI agent through tmux using a small XML message protocol. Use when Codex needs to send work to an agent in another tmux pane, request help from a peer agent, or respond to a structured tmux protocol message containing tmuxp-requester, tmuxp-replier, tmuxp-name, tmuxp-request, tmuxp-request-id, tmuxp-reply-id, tmuxp-reply, or tmuxp-error tags.
---

# Talk

## Overview

Use this skill to communicate with another agent that is already running in a tmux pane. Send requests and replies as plain XML fragments so both sides can reliably identify the requester, identify the replier, correlate replies, and distinguish successful answers from errors.

For the exact wire format, required tags, escaping rules, and examples, read `references/protocol.md`.

## Workflow

1. Identify the target tmux pane.
   - Prefer a user-provided pane target when available.
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
   - Do not run extra `tmux capture-pane`, `sleep`, or polling commands.
   - The receiving agent is responsible for sending a reply back to the tmux target in `<tmuxp-requester>`.
6. When receiving a tmuxp request, do the requested work if it is in scope, then send a tmuxp reply or error to the requester pane.

## Helper

Use the included send-only helper for normal requests and replies. It sends to an existing pane only.

```bash
/Users/jun/code/mine/research/.agents/skills/talk/scripts/tmuxp request --to <target-pane> --name codex-main -- "Summarize the failing test output."
```

For longer messages, use stdin:

```bash
/Users/jun/code/mine/research/.agents/skills/talk/scripts/tmuxp request --to <target-pane> --name codex-main --stdin
```

Replies and errors include both requester and replier panes:

```bash
/Users/jun/code/mine/research/.agents/skills/talk/scripts/tmuxp reply --to <requester-pane> --request-id <request-id> --name reviewer -- "No issues found."
/Users/jun/code/mine/research/.agents/skills/talk/scripts/tmuxp error --to <requester-pane> --request-id <request-id> --name reviewer -- "I cannot inspect the target pane."
```

Do not run a bare `scripts/tmuxp` from the repository or shell cwd. Resolve the helper relative to this skill directory, then invoke that path.

The helper resolves the current pane for `auto` requester or replier values during real sends, generates ids when requested, escapes payloads safely into a single-line XML fragment, pastes the fragment through a temporary tmux buffer that is deleted after paste, waits briefly, and submits it with `tmux send-keys Enter`. With `--dry-run`, unresolved `auto` pane values print as the literal placeholder `auto`; pass explicit pane values when the dry-run output must be a sendable protocol fragment.

## Receiving Requests

When a tmuxp request arrives in your pane:

- Parse the tmuxp tags before acting.
- Treat `<tmuxp-request>` content as the task payload.
- Do not invent missing context; ask back with a tmuxp reply if the request is ambiguous.
- Include the original `<tmuxp-request-id>` in every reply or error.
- Include a new `<tmuxp-reply-id>` in every reply or error.
- Keep final replies concise and actionable.

## Reference

Read `references/protocol.md` when you need to construct, parse, validate, or troubleshoot tmuxp messages.
