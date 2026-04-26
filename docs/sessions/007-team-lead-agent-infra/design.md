# Team Lead Agent Infra

## Context

The agent-team workflow uses three narrow skills:

- `summon` starts teammate agents and handles lifecycle commands.
- `roster` discovers live agent panes.
- `talk` sends structured request/reply messages between panes.

A recent team-lead test exposed two infrastructure problems:

1. Replies filled `<tmuxp-replier>` with the wrong pane id. The reply appeared to come from the lead pane instead of the teammate pane.
2. The lead role was underspecified. The lead duplicated teammate work and used `tmux capture-pane` to inspect teammates, which weakens the intended context isolation.

The useful pattern is still valid: a lead coordinates bounded teammate work and receives explicit protocol replies. The infra should make that pattern easier to follow and harder to misuse.

## Goals

- Fix `talk` replies so `<tmuxp-replier>` identifies the actual replying pane.
- Add a repo-local `team-lead` skill that records the lead's coordination rules.
- Preserve teammate signal in the final result instead of reducing everything to a lossy summary.
- Make pane inspection an explicit recovery/debug action, not a normal waiting strategy.

## Non-Goals

- No persistent team registry.
- No task-status database.
- No automatic scheduler.
- No health checker or readiness detector.
- No cross-socket messaging.
- No new polling mechanism.

## Talk Replier Id Fix

Patch `.agents/skills/talk/scripts/tmuxp` so `reply` and `error` resolve the replier pane from the sending pane, not from the requester or destination pane.

Expected behavior:

- A normal request includes `<tmuxp-requester>` for the pane that should receive the answer.
- A reply includes `<tmuxp-replier>` for the pane that is sending the reply.
- `--replier auto` should resolve to the current tmux pane when the helper runs inside the replying teammate pane.
- Dry-run behavior may keep unresolved `auto` as a placeholder, matching existing helper conventions.
- The helper should not silently emit a reply that claims the requester is also the replier unless the helper is actually running in that same pane.

Update `talk` documentation and protocol references where they describe reply construction.

## Team Lead Skill

Create a new repo-local skill:

```text
.agents/skills/team-lead/
├── SKILL.md
└── agents/openai.yaml
```

The skill triggers when Codex is asked to act as a team lead, coordinate teammate agents, delegate work through `summon`/`roster`/`talk`, or run parallel agent reviews.

Core rules for `SKILL.md`:

- Use `summon` to start teammates when needed.
- Use `roster` to discover or verify teammate panes when needed.
- Use `talk` to assign work and receive replies.
- Scope each teammate request clearly and avoid overlapping ownership unless overlap is intentional.
- Do not duplicate teammate work unless the user explicitly asks for fallback work.
- Do not use `tmux capture-pane` or pane inspection to poll teammates during normal operation.
- Preserve context isolation: teammate work should return through `talk` replies.
- If pane inspection is needed for infra recovery or debugging, state that reason and keep it narrow.
- Present results with both synthesis and per-teammate detail.
- Report missing replies, disagreements, blocked teammates, or infra failures explicitly.
- Dismiss or close teammates that the lead summoned when the work is done.

## Result Presentation

The lead should not only summarize. A good final response should include:

- a short synthesis of the overall result;
- each teammate's role and main output;
- disagreements or materially different recommendations;
- missing or failed replies;
- any infra actions taken, such as recovery inspection or teammate dismissal.

This preserves useful detail while still giving the user a readable lead-level answer.

## Error Handling

If a teammate does not reply through `talk`, the lead should not immediately poll panes. The lead should first wait for protocol replies in the normal conversation flow. Pane inspection is reserved for explicit recovery/debug situations, such as diagnosing a suspected approval prompt or failed helper invocation.

If recovery inspection is used, the final answer should say so. This keeps exceptional infra work visible instead of making it part of the normal collaboration pattern.

## Testing

Add focused Bats coverage for the `talk` helper:

- `reply` emits `<tmuxp-replier>` as the current pane when run inside a fake tmux pane.
- `error` emits `<tmuxp-replier>` as the current pane.
- explicit `--replier <pane>` still works.
- dry-run behavior remains stable for unresolved `auto`.

Validate the new skill with the skill validation helper from `skill-creator`.

Forward-testing the `team-lead` skill can be done later with a fresh agent-team task. The validation prompt should ask the lead to coordinate teammates and should not include these known failure modes, so the test checks whether the skill generalizes.
