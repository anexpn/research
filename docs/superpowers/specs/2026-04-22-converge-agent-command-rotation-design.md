# Converge Agent Command Rotation Design

**Goal**

Allow the converge runners to rotate agent commands independently from prompts, while preserving the existing sequential loop, prompt-list contract, and single-command behavior.

**Scope**

- Make `--agent-cmd` repeatable in `scripts/converge.py`, `scripts/converge.sh`, and `scripts/converge.rb`.
- Preserve existing behavior when exactly one `--agent-cmd` is provided.
- Keep prompt rotation file-based through `--prompt-list`.
- Record the selected agent command in step artifacts and loop logs for auditability.
- Keep `--tmux` and non-`--tmux` modes behaviorally aligned.

**CLI**

- `--agent-cmd` may be passed one or more times.
- Repeated `--agent-cmd` flags are stored in the order provided on the command line.
- A single `--agent-cmd` remains the default and behaves exactly like the current contract.
- Help text and examples must show both the single-command case and the repeated-command rotation case.

**Runtime Model**

- For step `N`, prompt selection remains `prompts[(N - 1) % prompt_count]`.
- For step `N`, command selection becomes `agent_cmds[(N - 1) % agent_cmd_count]`.
- Prompt rotation and command rotation are independent. Different list lengths are allowed and require no special alignment logic.
- The loop remains strictly sequential. Step `N+1` starts only after step `N` exits and `exit_code.txt` is written.

**Execution Strategy**

- Each runner normalizes parsed CLI input into a non-empty ordered list of agent commands.
- The selected command is computed inside the per-step loop and passed into the existing execution path for that step.
- In `--tmux` mode, the per-step wrapper must receive only the selected command for that step, not the full command list.
- In non-`--tmux` mode, the selected command is executed directly through the existing shell invocation path.

**Artifacts**

- `effective_prompt.md` must include the selected command in the runtime header for that step.
- `loop.log` must append the selected command to each step entry.
- Existing artifacts remain canonical:
  - `handoff.md`
  - `effective_prompt.md`
  - `stdout.log`
  - `stderr.log`
  - `exit_code.txt`

**Failure Handling**

- The runners must still reject invocation when no `--agent-cmd` is provided.
- There is no silent fallback or inferred default command.
- Rotation logic must not change existing prompt validation, tmux validation, or step failure behavior.

**Testing**

- Add contract tests that verify repeated `--agent-cmd` rotates independently from prompts in Python, shell, and Ruby.
- Keep or extend tests that prove the single-command case still behaves as before.
- Verify `--tmux` mode preserves the same per-step command selection as non-`--tmux` mode.
- Prefer black-box assertions against per-step artifacts and loop logs rather than parser internals.

**Non-Goals**

- No new prompt-list syntax.
- No separate command-list file.
- No command-to-prompt affinity rules.
- No concurrency or scheduling changes beyond independent modulo rotation.
