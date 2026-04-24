---
name: build-review-loop
description: Run a rotating Builder and Reviewer loop from a markdown design spec. Use when Human wants an iterative implementation-review cycle, wants Builder and Reviewer prompt files generated from a design/spec document, or wants a converge.sh run or resume command assembled for repeated agent handoffs.
---

# Build Review Loop

Use this skill to run a two-role rotating loop with the bundled prompts, `scripts/render_prompts.py`, and `scripts/converge.sh`.

## Require a design spec

- Require one markdown design/spec file that states what to build.
- If Human already provided the path, accept it and do not ask again.
- If the path is missing, ask only for that path first.
- Do not proceed without this file.
- Resolve the design spec path to an absolute path before rendering prompts or assembling commands.

## Keep the interaction portable

- Ask exactly one unresolved question per turn.
- Do not bundle multiple decisions in one turn.
- Prefer a structured-choice UI when the available options are finite.
- Fall back to conversational questions when no structured-choice UI is available.
- Use free-text questions only for arbitrary paths, custom commands, or `other` requirement details.
- After each answer, restate the resolved value briefly and move to the next unresolved item.
- Never skip ahead while an earlier item is unresolved.

## Use these defaults

- Store prompt files.
- Write prompt files next to the design spec:
  - `build-review-loop.builder.prompt.md`
  - `build-review-loop.reviewer.prompt.md`
- Use one agent source for both roles.
- Use `--max-steps 10`.
- Use session storage with `converge.sh`'s default temp session dir.
- Keep `--tmux`, `--tmux-cleanup`, `--tmux-session-name`, and `--dry-run` unset unless Human explicitly asks for them.
- Leave Builder and Reviewer special requirements empty unless Human selects them.

## Ask in this order

1. Ask for the design spec path if it is missing.
2. Ask for the initial settings selection with these concrete multi-select options:
   - `Use all default settings`
   - `Do not store prompt files`
   - `Use different agent sources for Builder and Reviewer`
   - `Set max steps to 4`
   - `Set max steps to 20`
   - `Choose a different session directory`
   - `Add Builder-specific requirements`
   - `Add Reviewer-specific requirements`
   Show the defaults in the question text.
3. If Builder-specific requirements were selected, ask for them using the options in `references/requirement-options.md`.
4. If Reviewer-specific requirements were selected, ask for them using the options in `references/requirement-options.md`.
5. Ask for agent source selection in all flows.
   Use one question when both roles share the same source.
   Use one question per role when Human selected split sources.
   Offer these choices:
   - `Use preset codex`
   - `Use preset claude`
   - `Use preset cursor-agent`
   - `Provide a custom agent command`
6. If Human selected `Provide a custom agent command`, ask only for the command string for the relevant role.
7. If Human selected `Choose a different session directory`, ask this exact three-option question:
   - `Use the default temp session directory`
   - `Use a different session directory`
   - `Do not use a session directory`
   Ask for a free-text path only if Human chooses `Use a different session directory`.

If Human selects only `Use all default settings`, keep every default and still ask only for agent source selection.

Do not ask a separate prompt-storage confirmation question. The initial settings selection already resolves that decision.

## Build prompts deterministically

Prompt text must be concise and complete.

- Tell, do not instruct.
- Avoid policy chatter.
- Keep each role focused on outcomes and artifacts.
- Frame the design spec as the authoritative implementation input, not as the artifact to rewrite, unless Human explicitly wants the design spec updated.
- Make the design spec stronger than the handoff. The handoff is continuity context, not the source of truth.
- Keep role-specific requirement text short and concrete.

When Human wants stored prompt files, render them with the bundled helper instead of editing templates by hand:

```bash
uv run python .agents/skills/build-review-loop/scripts/render_prompts.py \
  "<absolute-design-spec.md>" \
  --builder-output "<design-spec-dir>/build-review-loop.builder.prompt.md" \
  --reviewer-output "<design-spec-dir>/build-review-loop.reviewer.prompt.md" \
  --builder-requirement "<builder-option>" \
  --reviewer-requirement "<reviewer-option>"
```

Use these bundled files:

- `prompts/builder_prompt.template.md`
- `prompts/reviewer_prompt.template.md`
- `references/requirement-options.md`
- `scripts/render_prompts.py`

If Human chose not to store prompt files, do not write them. Use that mode only for run-now execution. If Human wants to self-run, require stored prompt files so the final command is stable and reviewable.

## Assemble the converge command

- Use `-A` for presets and `-a` for custom commands.
- Rotate Builder then Reviewer prompt sources in order.
- Use `-s` only when a custom session dir is enabled.
- Use `--no-session-dir` when Human explicitly chose not to use a session directory.
- Use `-n` only when the step count differs from the script default or when showing the chosen explicit value helps clarity.
- Keep tmux-related flags at defaults unless Human explicitly asked for them.
- For risk review, resolve every selected preset to its concrete agent command before deciding whether the run is safe enough to present without caveat. Do not treat a raw `-A <preset>` token as evidence that no risky flags are present.
- Keep the design spec authoritative across every step. Do not let a prior handoff redefine the required work.

Default shape:

```bash
bash .agents/skills/build-review-loop/scripts/converge.sh run \
  -A codex \
  -f "<design-spec-dir>/build-review-loop.builder.prompt.md" \
  -f "<design-spec-dir>/build-review-loop.reviewer.prompt.md" \
  -n 10
```

If Human chose a custom session dir and it already contains `run/meta`, prefer `converge.sh resume -s "<session-dir>"` instead of starting a fresh run. Ask for a positive `--additional-steps` value only when Human wants to run more steps beyond the current end.

## Call out risky flags

Before presenting the final command, inspect both:

- the command you plan to show Human
- the resolved agent commands behind any selected presets

A command that only shows `-A codex`, `-A claude`, or `-A cursor-agent` can still carry risky flags through the preset expansion, and those flags must be called out explicitly.

Current preset expansions to use for the final risk review:

- `codex` => `codex exec --dangerously-bypass-approvals-and-sandbox -`
- `claude` => `claude -p --permission-mode bypassPermissions`
- `cursor-agent` => `cursor-agent -p --yolo --trust --approve-mcps`

Treat these as risky when present in either the shown command or any resolved preset command:

- `--dangerously-bypass-approvals-and-sandbox`
- `--permission-mode bypassPermissions`
- `--yolo`
- `--trust`
- `--approve-mcps`

When a risky flag comes from a preset, say so directly, for example `--yolo` via preset `cursor-agent`.

If none are present after resolving presets, say that no known risky flags were detected.

## Finish with one final decision

When all inputs are clear:

1. Present the final command first.
2. List the exact risky flags present in that command or implied by the selected presets, if any.
3. Ask: `Run it now or do you want to run it yourself?`
4. Run it only if Human explicitly asks you to run it.

If Human chooses self-run, stop after presenting the command and the quick caveats.
