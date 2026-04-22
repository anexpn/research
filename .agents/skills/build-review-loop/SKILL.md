---
name: build-review-loop
description: Runs a rotating Builder and Reviewer loop from a markdown build brief with concise role prompts and a confirmed run command.
license: MIT
metadata:
  author: Jun <875241499@qq.com>
  version: "1.0.2"
---

# Build Review Loop

Use this skill to run a two-role rotating loop with the bundled `scripts/converge.sh`:

- Builder implements.
- Reviewer evaluates and requests concrete deltas.

## When to use

Use this skill when the user wants an iterative Builder <-> Reviewer cycle driven by a written build brief.

## Required input

The user must provide one markdown file that states what to build.

- If the user already provided a build brief path, accept it and do not ask again.
- Ask for the path only when it has not been provided yet.
- Do not proceed without this file.

## Question flow

Gather inputs in a strict one-question-at-a-time sequence.

- Ask exactly one unresolved question, then wait for the answer.
- Do not bundle multiple decisions in one turn.
- Re-ask only the single blocked question when clarification is needed.
- After each answer, restate the resolved value briefly and ask the next question.
- Keep a small internal decision list and only advance to the next unresolved item.

Use `AskQuestion` whenever the answer can be represented as fixed options. This is the default behavior, not an optional preference.

Use `AskQuestion` for:

- binary choices (yes/no),
- enumerations (preset lists),
- confirmation picks (final run-now vs self-run after command preview),
- single-select and multi-select option sets.

Use free-text questions only when the answer cannot be represented as options (for example, arbitrary file paths). If `AskQuestion` is unavailable, ask conversationally but still keep one question per turn.

### Ordered question checklist

Ask these in order, one per turn:

1. Initial settings selection. Ask this first with `AskQuestion` using concrete alternatives, not abstract "customize" labels:
   - `Use all default settings`
   - `Do not store prompt files`
   - `Use different agents for Builder and Reviewer`
   - `Set max steps to 4`
   - `Set max steps to 20`
   - `Choose a different session directory option`
   Use multi-select for these options. Show defaults as a list in the prompt text, for example:
   - `Default: Store prompt files`
   - `Default: Use one agent for both roles`
   - `Default: Max steps = 10`
   - `Default: Session directory = <computed-session-dir>`
   Also state that selecting only `Use all default settings` keeps defaults, while selecting any other option applies only those changes. Agent type is always asked separately.
2. Build brief path only when missing (for example: `What's the path to your build brief markdown file?`).
3. Builder-specific requirements via `AskQuestion` (multi-select) with concrete options plus `none`.
4. Reviewer-specific requirements via `AskQuestion` (multi-select) with concrete options plus `none`.
5. Prompt storage decision only when `Do not store prompt files` is selected.
6. Agent assignment mode only when `Use different agents for Builder and Reviewer` is selected.
7. Agent details:
   - Ask agent type in all modes using `AskQuestion` (options: `claude`, `codex`, `cursor-agent`).
   Collect role-specific values only when split is requested.
8. Max steps follow-up:
   - If one of the concrete max-step options was selected, apply that value directly and do not ask another max-steps question.
   - If no max-step override option was selected, keep default `10`.
9. Session dir usage as a 3-option choice only when `Choose a different session directory option` is selected. Show the computed path and ask the user to pick one option:
   - `Use this session directory: <computed-session-dir>`
   - `Use a different session directory`
   - `Do not use a session directory`

If the user selects only `Use all default settings`, skip optional override questions and keep default values.
If the user selects one or more override options, ask only the follow-up questions for those selected options.

Even in defaults mode, still ask for agent type (`claude`, `codex`, or `cursor-agent`) and use that selection.

When default session directory is in effect, do not ask a separate session-choice question again.
Use the 3-option session-choice question only when `Choose a different session directory option` was selected.
If the user picks `Use this session directory`, proceed with the shown path. If they pick `Use a different session directory`, ask for custom path. If they pick `Do not use a session directory`, do not set `--session-dir`.

For Builder/Reviewer special requirements, do not ask as plain free text when `AskQuestion` is available.
Use `AskQuestion` with a multi-select list of concrete requirement options and include `none`.
Include an `other` option only if needed; if selected, collect short free-text details in the next turn.

If a build brief path was already provided in the user's initial request, restate and confirm that value briefly, then continue to the next unresolved item without re-asking for the path.

Never skip ahead while an earlier item is unresolved.

## Role prompt style

Prompt text must be concise and complete.

- Tell, do not instruct.
- Avoid policy chatter.
- Keep each role focused on outcomes and artifacts.

## Prompt construction

Build two prompts: Builder and Reviewer.

Each prompt should include:

1. role identity,
2. expected output artifact for each step,
3. the build brief markdown path,
4. role-specific requirements provided by the user (if any),
5. handoff expectation to the next role.

Keep both prompts short and direct.

Default templates:

- `prompts/builder_prompt.template.md`
- `prompts/reviewer_prompt.template.md`

## Prompt file handling

Ask if the user wants to store prompt files when that decision is still unresolved (for example, during customize mode).

Inference order:

1. If project convention is clear, use that convention.
2. Otherwise place prompt files next to the build brief markdown.

If the user chooses to store prompt files, infer prompt-file paths and write them without a separate path-confirmation question. Use `AskQuestion` when possible.

Do not ask `Use the inferred prompt file paths?`.

When asking this, use natural wording like: `Do you want me to store the prompt files?`

Do not write prompt files without explicit approval.

Do these steps directly in the skill flow (do not rely on `init_build_review_loop.sh`):

- infer prompt output location by convention or brief-relative fallback,
- write builder/reviewer prompt files from templates,
- inject the resolved build brief path.

## Converge option confirmation

After prompts are ready, ask the user only for remaining unresolved script options and show inferred defaults.

Infer defaults from the bundled `scripts/converge.sh`:

- `--max-steps`: `10`
- `--session-dir`: optional but recommended for artifacts
- handoff: enabled when `--session-dir` is provided, otherwise disabled
- agent source: always select agent type via `-A` (`claude`, `codex`, or `cursor-agent`)

If defaults mode is selected, keep default values for everything else, but still ask and apply agent type.

When `--session-dir` is considered, compute the path from the build brief location (following project conventions when available) and present this exact 3-option choice:

1. `Use this session directory: <computed-session-dir>`
2. `Use a different session directory`
3. `Do not use a session directory`

Do not describe option 1 as "inferred path" in the user-facing question.

Do not ask proactive questions about `--tmux`, `--tmux-cleanup`, `--tmux-session-name`, or `--dry-run`. Keep them at defaults unless the user explicitly requests them.

Do not re-ask agent split/agent source questions if they were already resolved in the ordered checklist. If still unresolved, ask them with the same wording and order defined there.

Do not ask `Which source type should be used for both roles?` and do not frame the question as `Agent preset (-A)`.

## Command assembly

Assemble a single `scripts/converge.sh run` command that rotates Builder and Reviewer prompts in order.

Example shape:

```bash
bash .agents/skills/build-review-loop/scripts/converge.sh run \
  -A codex \
  -f "<builder-prompt.md>" \
  -f "<reviewer-prompt.md>" \
  -s "<session-dir>" \
  -n 10
```

## Final handoff step

When all inputs are clear:

1. present the final command,
2. warn that selected agent presets/commands may include dangerous permission bypass flags and show the exact risky flags present in the command,
3. ask: `Run it now or do you want to run it yourself?`
4. run only if the user explicitly asks the agent to run it.

Never ask step 3 before step 1. The command must be shown first in the same turn, then ask the run-now vs self-run choice.

Ask step 3 as a structured single-choice question when the tool is available.

If the user chooses self-run, stop after presenting the command and any quick caveats.

## Utility files

- Prompts:
  - `prompts/builder_prompt.template.md`
  - `prompts/reviewer_prompt.template.md`
- Scripts:
  - `scripts/converge.sh`
