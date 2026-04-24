# Commit Agent Wrapper Design

## Goal

Create a small `bash` script that does one job well:

1. inspect the current change,
2. ask a coding agent for a commit message,
3. create the commit itself.

The script must support:

- agents: `codex`, `claude`, `cursor-agent`
- VCS: `git`, `jj`
- sensible defaults with minimal required arguments
- a built-in default prompt/template that can be overridden
- repo-history learning as secondary context
- conventional commits as the default style
- `bats` coverage

The wrapper, not the agent, performs the commit.

## Non-Goals

- staging files
- splitting commits
- generating changelogs
- interactive commit editing
- general agent orchestration
- project-specific configuration files in the first version

## High-Level Approach

Implement a single `bash` script named `commit.sh`.

The script will:

1. infer the VCS, preferring `jj`
2. infer or accept an agent preset
3. collect the relevant diff
4. collect recent commit subjects as style context
5. build a prompt from a default template or override
6. run the selected agent CLI with built-in default flags
7. normalize the returned commit message
8. run `git commit` or `jj commit` itself

This keeps the tool narrow and predictable. The agent only proposes text.

## CLI Surface

The initial interface should stay small:

```bash
commit.sh \
  [--agent codex|claude|cursor-agent] \
  [--vcs git|jj] \
  [--style conventional|repo|prompt] \
  [--template-file PATH] \
  [--prompt TEXT] \
  [--agent-arg ARG]
```

Behavior notes:

- `--agent` selects the built-in agent preset.
- `--vcs` overrides inference.
- `--style conventional` is the default.
- `--style repo` asks the agent to follow the repo’s dominant recent subject pattern instead of conventional commits.
- `--style prompt` means the caller is supplying explicit convention guidance with `--prompt`.
- `--template-file` replaces the built-in prompt template.
- `--prompt` injects explicit user guidance. It is required for `--style prompt` and optional otherwise.
- `--agent-arg` is repeatable and appends extra CLI arguments after the preset defaults.

The first cut should require `--agent`. Agent inference can be added later if it proves necessary.

## VCS Detection And Diff Rules

VCS inference must prefer `jj`.

Rules:

1. If `--vcs` is provided, use it.
2. Otherwise, if the current directory is inside a `jj` repo, use `jj`.
3. Otherwise, if the current directory is inside a `git` repo, use `git`.
4. Otherwise, fail with a clear error.

Diff collection rules:

- `git`: inspect only staged changes and commit only staged changes.
- `jj`: inspect the current working-copy diff and commit that diff.

Commands:

- `git` diff source: `git diff --cached`
- `jj` diff source: `jj diff --git`

Empty-change behavior:

- `git`: fail if `git diff --cached --quiet` indicates nothing staged
- `jj`: fail if `jj diff --git` is empty

## Agent Presets

The script will hardcode default non-interactive commands for each agent preset.

Initial presets:

- `codex`: `codex exec --dangerously-bypass-approvals-and-sandbox -`
- `claude`: `claude -p --permission-mode bypassPermissions`
- `cursor-agent`: `cursor-agent -p --yolo --trust --approve-mcps`

The script feeds the prompt on stdin when appropriate for the preset.

`--agent-arg` values are appended after the built-in preset command. This keeps the common path simple while still allowing overrides for edge cases.

The script should print the resolved agent command on failure to aid debugging, but avoid noisy logging on success.

## Prompt And Style Policy

The script will ship with a built-in default template. No external template file is required for normal use.

Default style policy:

- `conventional` is the default output format
- recent commit subjects from the repo are still included as secondary context
- the prompt must explicitly say that conventional commits take priority unless another style is requested

Style modes:

- `conventional`: ask for a conventional commit subject, optionally followed by a body only if warranted by the diff
- `repo`: ask the agent to learn and follow the dominant pattern in recent commit subjects
- `prompt`: ask the agent to follow the user-provided guidance in `--prompt`

Prompt inputs:

- selected style mode
- optional user guidance from `--prompt`
- the change diff
- recent commit subjects

Prompt output contract:

- return only the commit message
- first line is the subject
- blank line plus body is allowed when useful
- no code fences
- no explanation
- no surrounding commentary

## Repo History Learning

Repo history should be lightweight and local.

The script samples the latest 12 commit subjects.

History collection:

- `git`: recent `git log --format=%s`
- `jj`: recent local commit subjects from `jj log`

History is used in two ways:

1. in `conventional` mode, as secondary context only
2. in `repo` mode, as the main style signal

The script does not need a complex classifier in the first version. It can provide the raw recent subjects directly to the agent. If there is later evidence that more structure is needed, the script can add lightweight heuristics.

## Commit Execution

The wrapper performs the commit after the agent returns a message.

Execution rules:

- if the message is empty after normalization, fail
- if the subject line is empty, fail
- preserve a multiline body when present

Commit commands:

- `git`: commit the already-staged changes using the generated message
- `jj`: create the commit from the working copy using the generated message

The script should write the generated message to a temp file and pass that file to the VCS commit command for multiline messages.

## Error Handling

The tool should fail fast and clearly.

Expected failures:

- unsupported or missing agent preset
- agent binary not found
- no staged diff in `git` mode
- no working-copy diff in `jj` mode
- unreadable template override file
- `--style prompt` without `--prompt`
- empty agent output
- VCS commit command failure

Error messages should state what the script expected and what the user can fix.

## Testing

Add `bats` integration tests around the script’s real behavior.

Test strategy:

- create temporary `git` and `jj` repos inside tests
- stub agent executables by placing fake `codex`, `claude`, or `cursor-agent` binaries first on `PATH`
- verify both the produced commit and the prompt inputs sent to the stub

Initial test matrix:

- VCS inference prefers `jj`
- explicit `--vcs` overrides inference
- `git` mode uses only staged diff
- `git` mode ignores unstaged changes
- `git` mode fails with nothing staged
- `jj` mode uses working-copy diff
- `jj` mode fails with no diff
- default style is `conventional`
- recent commit subjects are passed as secondary context in default mode
- `--style repo` changes prompt policy to follow repo history
- `--style prompt` requires and uses user guidance
- template override replaces the default template
- each agent preset resolves to the expected default command
- repeated `--agent-arg` values are appended
- wrapper performs the commit instead of delegating commit execution to the agent
- multiline commit messages are preserved

## File Layout

First version should stay minimal.

Planned files:

- `commit.sh`
- `tests/commit_sh.bats`

If the script later grows too large, prompt helpers can be extracted. The first version should avoid premature modularization.

## Recommendation

Build the first version as a single `bash` script with `bats` integration tests, default to conventional commits, include recent history as secondary context, prefer `jj` when inferring VCS, and keep commit execution entirely inside the wrapper.
