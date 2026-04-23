# Converge Run-To-Completion Design

**Goal**

Add `--run-to-completion` to `scripts/converge.sh` so the loop can end before `--max-steps` when the agents repeatedly judge that the entire assigned work is finished.

**Scope**

- Add `--run-to-completion` to `scripts/converge.sh`.
- Keep `--max-steps` as a hard upper bound.
- Require `--session-dir` and handoff mode for `--run-to-completion`.
- Define a strict handoff-based completion judgement contract that agents can emit reliably.
- Persist enough metadata for `resume` to preserve the same mode and recover the current completion streak from artifacts.
- Update shell tests and `scripts/converge.md`.

**Completion Model**

- Completion is about the whole converge assignment, not the current step.
- A step may judge the work `complete` only when the agent believes the overall assignment is finished and the loop can stop if the next step independently agrees.
- A step must judge the work `incomplete` when any additional implementation, review, verification, or uncertainty remains, even if the current agent finished its own local contribution.
- A single `complete` is only a candidate signal.
- Real completion requires `2` consecutive completed steps whose handoffs both declare `complete`.
- Any `incomplete`, missing judgement, malformed judgement, or missing handoff resets the completion streak to `0`.

**CLI**

- Add `--run-to-completion` as a run-only flag.
- `--run-to-completion` is invalid without `--session-dir`.
- `--run-to-completion` is invalid with `--no-handoff`.
- `resume` does not accept a new completion-mode flag. It inherits the stored mode from the original run.
- `--max-steps` remains required to be positive and remains the ceiling even when run-to-completion is enabled.
- `--dry-run` must print:
  - `completion_mode=fixed_steps` or `completion_mode=run_to_completion`
  - `completion_streak_target=2` when run-to-completion is enabled

**Handoff Contract**

When `--run-to-completion` is enabled, every completed step must write `handoff.md` with YAML frontmatter at the top:

```md
---
converge_work_judgement: incomplete
converge_reason: more validation is needed
---
```

Rules:

- `converge_work_judgement` is required.
- Allowed values are `complete` and `incomplete`.
- `converge_reason` is recommended but optional. It is for human inspection and logging context, not runner control flow.
- The runner only parses the frontmatter block at the top of `handoff.md`.
- Anything after the frontmatter remains free-form handoff prose.

**Agent Instructions**

When `--run-to-completion` is enabled, the effective prompt must explicitly tell the agent:

- write `handoff.md` for this step
- include YAML frontmatter with `converge_work_judgement`
- use `complete` only if the entire assignment appears finished and the loop should stop if the next step independently agrees
- use `incomplete` if the current step is done but any further work, review, checking, or uncertainty remains

This instruction belongs in the runtime protocol section so it is attached automatically to every role prompt.

**Runtime Model**

- The loop remains sequential.
- After each step exits, the runner records normal artifacts first.
- If run-to-completion is disabled, behavior is unchanged.
- If run-to-completion is enabled, the runner inspects that step's `handoff.md`, extracts `converge_work_judgement`, updates the completion streak, and decides whether to stop early.
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
- If `--run-to-completion` is used with `--no-handoff`, exit with a clear CLI error.
- If a step exits but produces no `handoff.md`, treat the judgement as missing, reset the streak to `0`, and continue.
- If the handoff frontmatter is missing, malformed, or contains an unsupported value, treat the judgement as missing, reset the streak to `0`, and continue.
- Missing or malformed judgement is not a fatal run error because the safer fallback is to continue until either later steps confirm completion or `--max-steps` is reached.

**Metadata And Artifacts**

- Add run metadata for `run_to_completion`.
- No new per-step artifact is needed; `handoff.md` remains the canonical completion signal source.
- `effective_prompt.md` should show the run-to-completion protocol text so each step can be audited after the fact.
- `loop.log` should append the parsed completion judgement and streak when run-to-completion is enabled.

**Testing**

- Add CLI tests that reject `--run-to-completion` without `--session-dir`.
- Add CLI tests that reject `--run-to-completion` together with `--no-handoff`.
- Add a black-box test where two consecutive steps emit `complete` and the loop exits before `--max-steps`.
- Add a test where one `complete` followed by `incomplete` resets the streak and does not stop the loop.
- Add a test where malformed or missing frontmatter is treated as `incomplete`.
- Add a resume test where an interrupted run with one trailing `complete` resumes and stops after the next `complete`.
- Add a resume test where completion was already confirmed before interruption and `resume` exits immediately.

**Non-Goals**

- No stdout sentinel parsing.
- No exit-code-based completion semantics.
- No role-aware completion logic.
- No configurable completion threshold in this change.
- No change to the default fixed-step behavior when `--run-to-completion` is not used.
