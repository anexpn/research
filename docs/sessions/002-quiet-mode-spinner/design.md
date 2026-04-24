# Quiet-Mode Spinner

## Goal

Show progress while `ideas/005-commit/commit.sh` is waiting on the agent, but only for interactive quiet-mode use.

## Decision

- Render an ASCII spinner on `stderr` only when `--verbose` is not set and `stderr` is a TTY.
- Clear the spinner line completely on both success and failure.
- Keep non-interactive and verbose behavior unchanged.

## Approaches Considered

1. Add the spinner directly in the quiet path after the agent process is started.
   This is the smallest change and keeps verbose behavior untouched.
2. Add a general command-wrapper helper.
   This is cleaner in isolation, but it adds abstraction the script does not otherwise need.
3. Use terminal-capability tooling such as `tput`.
   This adds more moving parts without improving the user-visible result.

Selected approach: add the spinner directly in the quiet path.

## Implementation Shape

- Start the quiet-path agent command in the background with temporary files for stdout and stderr.
- While the process is running, animate a spinner on `stderr`.
- Clear the line before returning control to the rest of the script.
- On failure, clear the line first, then dump captured agent stderr.
- Extend the `bats` suite to cover:
  - spinner visible in interactive quiet mode
  - spinner absent in interactive verbose mode
  - spinner absent when stderr is not a TTY
