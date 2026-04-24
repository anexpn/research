# Converge Run-To-Completion Design

**Goal**

Add `--run-to-completion` to `scripts/converge.sh` so the loop can end before `--max-steps` when the agents repeatedly judge that the entire assigned work is finished.

**Scope**

- Add `--run-to-completion` to `scripts/converge.sh`.
- Keep `--max-steps` as a hard upper bound.
- Require `--session-dir` for `--run-to-completion`.
- Keep handoff and run-to-completion independent so either can be enabled without the other.
- Define a strict completion-artifact contract that agents can emit reliably.
- Persist enough metadata for `resume` to preserve the same mode and recover the current completion streak from artifacts.
- Update shell tests and `scripts/converge.md`.

**Completion Model**

- Completion is about the whole converge assignment, not the current step.
- A step may judge the work `complete` only when the agent believes the overall assignment is finished and the loop can stop if the next step independently agrees.
- A step must judge the work `incomplete` when any additional implementation, review, verification, or uncertainty remains, even if the current agent finished its own local contribution.
- A single `complete` is only a candidate signal.
- Real completion requires `2` consecutive completed steps whose completion artifacts both declare `complete`.
- Any `incomplete`, missing judgement, malformed judgement, or missing completion artifact resets the completion streak to `0`.

**CLI**

- Add `--run-to-completion` as a run-only flag.
- `--run-to-completion` is invalid without `--session-dir`.
- `--run-to-completion` remains valid with `--no-handoff`.
- `resume` does not accept a new completion-mode flag. It inherits the stored mode from the original run.
- `--max-steps` remains required to be positive and remains the ceiling even when run-to-completion is enabled.
- `--dry-run` must print:
  - `completion_mode=fixed_steps` or `completion_mode=run_to_completion`
  - `completion_streak_target=2` when run-to-completion is enabled
  - `output_completion=<session-dir>/run/sNNN/completion_status.txt` for each planned step when run-to-completion is enabled

**Completion Contract**

When `--run-to-completion` is enabled, every completed step must write `completion_status.txt` containing exactly one trimmed token:

```txt
incomplete
```

Rules:

- Allowed values are `complete` and `incomplete`.
- Any surrounding whitespace is ignored.
- Any other content is treated as malformed.
- `handoff.md` remains free-form continuity context when handoff mode is enabled, but it is not part of completion control flow.

**Agent Instructions**

When `--run-to-completion` is enabled, the effective prompt must explicitly tell the agent:

- write `completion_status.txt` for this step
- write exactly one judgement token: `complete` or `incomplete`
- use `complete` only if the entire assignment appears finished and the loop should stop if the next step independently agrees
- use `incomplete` if the current step is done but any further work, review, checking, or uncertainty remains
- keep handoff writing separate; if handoff is enabled, it remains advisory continuity only

This instruction belongs in the runtime protocol section so it is attached automatically to every role prompt.

**Runtime Model**

- The loop remains sequential.
- After each step exits, the runner records normal artifacts first.
- If run-to-completion is disabled, behavior is unchanged.
- If run-to-completion is enabled, the runner inspects that step's `completion_status.txt`, updates the completion streak, and decides whether to stop early.
- The loop stops early only when the current streak reaches `2`.
- If early stop happens, the runner prints a specific completion confirmation line instead of relying only on the generic final summary.

Recommended operator-facing output:

- startup:
  - `completion_mode=run_to_completion`
  - `completion_streak_target=2`
- per step:
  - `completion_judgement=complete streak=1/2`
  - `completion_judgement=incomplete streak=0/2`
- early stop:
  - `Completion confirmed at step 6 after 2 consecutive complete judgements.`

**Resume Semantics**

- Persist `run_to_completion` in run metadata.
- `resume` loads the stored completion mode before deciding how many steps remain.
- On `resume`, the runner recomputes the trailing completion streak from completed step artifacts rather than trusting transient process state.
- Recomputed streak uses only the contiguous suffix of completed steps ending at the latest completed step.
- If the last completed step already satisfied the `2`-step completion rule, `resume` prints that completion has already been confirmed and exits without running another step.
- If the last completed step ended with one trailing `complete`, `resume` continues with streak `1`.
- Historical malformed or missing judgements break the streak the same way they do during a live run.

**Failure Handling**

- If `--run-to-completion` is used without `--session-dir`, exit with a clear CLI error.
- `--no-handoff` does not affect run-to-completion semantics.
- If a step exits but produces no `completion_status.txt`, treat the judgement as missing, reset the streak to `0`, and continue.
- If `completion_status.txt` is empty, malformed, or contains an unsupported value, treat the judgement as missing, reset the streak to `0`, and continue.
- Missing or malformed judgement is not a fatal run error because the safer fallback is to continue until either later steps confirm completion or `--max-steps` is reached.

**Metadata And Artifacts**

- Add run metadata for `run_to_completion`.
- Add a per-step `completion_status.txt` artifact that is only used when run-to-completion is enabled.
- `effective_prompt.md` should show the run-to-completion protocol text so each step can be audited after the fact.
- `loop.log` should append the parsed completion judgement and streak when run-to-completion is enabled.

**Testing**

- Add CLI tests that reject `--run-to-completion` without `--session-dir`.
- Add CLI tests that show `--run-to-completion` still works together with `--no-handoff`.
- Add a black-box test where two consecutive steps emit `complete` and the loop exits before `--max-steps`.
- Add a test where one `complete` followed by `incomplete` resets the streak and does not stop the loop.
- Add a test where malformed or missing completion-status content is treated as `incomplete`.
- Add a resume test where an interrupted run with one trailing `complete` resumes and stops after the next `complete`.
- Add a resume test where completion was already confirmed before interruption and `resume` exits immediately.

**Non-Goals**

- No stdout sentinel parsing.
- No exit-code-based completion semantics.
- No role-aware completion logic.
- No configurable completion threshold in this change.
- No change to the default fixed-step behavior when `--run-to-completion` is not used.
