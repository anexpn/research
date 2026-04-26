---
name: team-lead
description: Coordinate teammate agents through summon, roster, and talk when asked to act as a team lead, delegate work, run parallel agent reviews, or synthesize teammate replies.
---

# Team Lead

Use this skill when Codex is asked to lead teammate agents, coordinate delegated work, run parallel agent reviews, or synthesize replies from agents reached through tmux.

## Core Workflow

1. Clarify the goal, deliverable, constraints, and any required teammate roles.
2. Use `summon` to start teammate agents when additional agents are needed.
3. Use `roster` to discover or verify teammate panes when working with existing agents or confirming launched panes.
4. Use `talk` to assign work and receive replies. Teammate context should return through explicit protocol replies.
5. Scope each teammate request with a clear role, task, owned files or topic area, expected output, and deadline or stopping point.
6. Avoid overlapping ownership unless the overlap is intentional, such as independent reviews of the same artifact.
7. Do not duplicate teammate work unless the user explicitly asks for fallback work.
8. Dismiss or close teammates that this lead summoned when the work is done.

## Context Isolation

- Do not use `tmux capture-pane` or pane inspection to poll teammates during normal operation.
- Wait for protocol replies in the normal conversation flow.
- If pane inspection is needed for infrastructure recovery or debugging, state the reason before using it and keep the inspection narrow.
- Examples of recovery reasons include a suspected approval prompt, a failed helper invocation, or diagnosing why a protocol reply cannot be sent.

## Result Handling

Track the expected replies and report gaps plainly:

- Include a short synthesis of the overall result.
- Include each teammate's role and main output.
- Preserve useful per-teammate detail instead of reducing all replies to one lossy summary.
- Call out disagreements or materially different recommendations.
- Report missing replies, blocked teammates, or infrastructure failures explicitly.
- Mention any recovery inspection, teammate dismissal, or other infrastructure action taken.

## Request Quality

Good teammate requests are bounded and self-contained. Include the relevant paths, commands, review focus, and the exact output shape needed. If multiple teammates are active, make ownership boundaries explicit so agents do not overwrite or duplicate each other's work.
