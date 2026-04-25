# Talk Protocol Helper Design

## Goal

Update the `talk` skill so agents can send structured tmuxp messages to an existing tmux pane with one focused command. The helper must not create tmux windows, launch Codex, discover target windows, or manage agent lifecycle.

## Protocol

Rename `<tmuxp-sender>` to role-specific tags:

- Requests use `<tmuxp-requester>` for the pane that should receive the response.
- Replies and errors include both `<tmuxp-requester>` and `<tmuxp-replier>`.
- Replies and errors include `<tmuxp-request-id>` and a generated `<tmuxp-reply-id>`.

The optional `<tmuxp-name>` remains a human-readable label for whichever agent is sending the current fragment.

## Helper

Add `.agents/skills/talk/scripts/tmuxp` with three subcommands:

- `request --to <pane> [--requester auto|pane] [--name name] [--request-id auto|id] -- <message>`
- `reply --to <pane> --request-id <id> [--requester pane] [--replier auto|pane] [--name name] [--reply-id auto|id] -- <message>`
- `error --to <pane> --request-id <id> [--requester pane] [--replier auto|pane] [--name name] [--reply-id auto|id] -- <message>`

Each command also supports `--stdin` for long payloads. Message files are not required.

## Data Flow

Agents should invoke the helper by resolving it relative to the talk skill directory, not by running a bare `scripts/tmuxp` from their current working directory.

For real sends, the helper resolves `auto` to the current pane with `tmux display-message -p '#{pane_id}'`, builds a single-line XML fragment, pastes it to the target pane through a temporary tmux buffer that is deleted after paste, waits briefly, and submits it with `tmux send-keys Enter`. With `--dry-run`, unresolved `auto` pane values print as the literal placeholder `auto` so XML construction can be checked without an accessible tmux client; callers should pass explicit pane values when dry-run output must be sendable as-is. Message newlines are encoded as XML character references so the final submit key is the only physical newline sent to the target pane.

The caller must provide the target pane. The helper does not inspect tmux windows except for current-pane resolution.

## Error Handling

The helper exits non-zero when required arguments are missing, a message is empty, tmux fails, or `--stdin` is combined with trailing message text. It keeps generated ids compact and deterministic enough for correlation: `req-YYYYMMDD-HHMMSS-<hex>` and `rep-YYYYMMDD-HHMMSS-<hex>`.

## Testing

Verify the script help, direct-message construction, stdin handling, and docs references. Since the helper sends to tmux panes, use dry-run output for message construction checks and avoid launching new windows during tests.
