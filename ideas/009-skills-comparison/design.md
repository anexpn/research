# Agent Skills Repo Comparison

## Context

This note compares three influential public repositories for AI coding-agent workflows:

- `addyosmani/agent-skills`
- `mattpocock/skills`
- `obra/superpowers`

All three package reusable "skills" for coding agents, but they are not interchangeable. Each encodes a different theory about where agent failures come from, how much process should be imposed, how much the repository itself should teach the agent, and how much autonomy should be granted once work begins.

At a high level:

- Addy assumes agents mostly fail by skipping engineering discipline.
- Matt assumes agents mostly fail by misunderstanding the repository and its language.
- Superpowers assumes agents mostly fail by drifting outside a mandatory end-to-end workflow once the session gets moving.

The comparison here is based on direct inspection of the public repositories, selected skill files, install docs, release notes, commit and release surfaces, and representative issues as of May 7, 2026.

## Summary

`addyosmani/agent-skills` is best understood as a process framework for agent-driven software delivery. It wraps skills inside a structured lifecycle with explicit phases, reusable commands, specialist personas, and quality gates. Its strength is standardized execution discipline across many contexts and tools.

`mattpocock/skills` is better understood as a repository-aware operating model for serious engineering work with agents. It focuses less on a universal lifecycle and more on preventing misalignment through shared language, issue-tracker integration, repo-specific documentation, and architectural scrutiny. Its strength is keeping the agent semantically aligned with the codebase and the team's working model.

`obra/superpowers` is best understood as an opinionated workflow runtime for coding agents. It does not just provide skills; it provides a mandatory sequence, bootstrap behavior, harness-specific installation and tool mapping, isolated worktree setup, detailed plan generation, and subagent-driven execution. Its strength is sustaining long autonomous implementation loops without letting the agent quietly switch back to ad hoc behavior.

In short:

- Addy optimizes for process discipline and portability.
- Matt optimizes for semantic alignment and project integration.
- Superpowers optimizes for workflow-enforced autonomy and execution throughput.

## Repository Positioning

### addyosmani/agent-skills

The repository presents itself as a complete system for "AI-powered software engineering." The packaging is intentionally broad:

- 20 core skills
- 7 slash commands
- 3 agent personas
- reference materials and setup docs for several agent environments

The top-level model is a staged SDLC workflow:

- define
- plan
- build
- verify
- review
- simplify
- ship

That staged framing is not cosmetic. The commands and skills are designed to pull the agent through those steps instead of leaving the sequencing to operator judgment.

### mattpocock/skills

The repository presents itself less as a formal lifecycle and more as a collection of sharp interventions against common agent failure modes. The README and exported skills emphasize:

- better planning
- stronger feedback loops
- domain understanding
- clearer issue decomposition
- architectural pressure against codebase sprawl

Instead of a fixed outer pipeline, the repo offers composable skills such as:

- `grill-me`
- `grill-with-docs`
- `tdd`
- `to-prd`
- `to-issues`
- `zoom-out`
- `improve-codebase-architecture`

This makes the repo feel less like a framework and more like a curated engineering operating system.

### obra/superpowers

The repository presents itself as a complete software development methodology for coding agents, not merely as a library of prompts. Its README defines a canonical workflow:

- `brainstorming`
- `using-git-worktrees`
- `writing-plans`
- `subagent-driven-development` or `executing-plans`
- `test-driven-development`
- `requesting-code-review`
- `finishing-a-development-branch`

What makes this distinct is the packaging around the skills:

- a meta-skill (`using-superpowers`) that forces skill lookup before action
- harness-specific install and tool-mapping docs
- explicit Codex, Claude Code, Cursor, Gemini CLI, OpenCode, Copilot CLI, and Factory Droid support
- plugin/bootstrap behavior intended to make the workflow self-starting inside the host tool

This makes Superpowers feel less like a skill collection and more like a workflow product.

## Core Thesis of Each Repo

### Addy's Thesis

The central claim behind `agent-skills` is that coding agents tend to skip the work that human teams rely on for quality:

- they under-specify
- they over-implement
- they rationalize skipping tests
- they avoid critical review
- they stop before deployment-grade verification

The repo's answer is explicit structure. Each skill is longer, more formal, and more resistant to agent shortcuts. The documented anatomy of a skill includes workflow stages, rationalization rebuttals, red flags, and verification expectations. The design assumes the agent must be constrained into good engineering behavior.

### Matt's Thesis

The central claim behind `skills` is that the biggest failures are often semantic, not procedural:

- the agent does not understand the codebase vocabulary
- the user and the code use different terms
- a plan sounds plausible but conflicts with existing docs or architecture
- work gets decomposed poorly across issues
- local implementation success still worsens the codebase

The repo's answer is not a giant fixed workflow. It is a set of skills that force the agent to interrogate ambiguity, align to repo-specific language, externalize work into issue-tracker units, and continuously zoom out to the larger design.

This is a narrower but more original thesis than "agents should follow TDD and review steps."

### Superpowers' Thesis

The central claim behind `superpowers` is that good local intentions are not enough. Even if the agent knows about TDD, planning, debugging, or review, it will still drift unless the whole session is kept inside a mandatory workflow:

- brainstorm before coding
- isolate the workspace before execution
- write an explicit plan before implementation
- drive execution task by task
- re-verify after every major step
- finish with an explicit branch/merge decision

The repo's answer is a chain of rigid skills, each of which assumes the previous one already ran. The design assumes that the agent should not merely be reminded to behave well; it should be continuously steered back into a predefined operating mode.

## Skill Design Style

### Addy: formal, self-contained, and procedural

Representative files such as `spec-driven-development`, `test-driven-development`, and the slash commands show a strong preference for procedural completeness. The skills tend to be:

- self-contained
- explicit about sequencing
- rich in checklists
- explicit about anti-patterns
- explicit about what counts as done

This is helpful when:

- users are less experienced
- teams want consistent outputs
- multiple agents need a shared workflow
- the execution environment changes often

The downside is weight. The repo can feel like a process shell wrapped around the work. In stronger hands, that can become friction.

### Matt: compact, pointed, and judgment-heavy

Representative files such as `grill-with-docs`, `tdd`, `to-prd`, and `setup-matt-pocock-skills` are usually shorter but denser. They tend to:

- assume the human can exercise judgment
- force the agent to clarify ambiguous concepts
- push work into real repo artifacts
- prefer vertical slices over abstract decomposition
- care about language, architecture, and interfaces more than ceremony

This is helpful when:

- the operator is technically strong
- the repository is long-lived and semantically messy
- issue trackers and docs are part of the real workflow
- the risk is "the agent is confidently wrong about the project"

The downside is that the repo asks more from the human and the surrounding system. It is not as turnkey.

### Superpowers: rigid, recursive, and workflow-enforcing

Superpowers is closer to Addy than to Matt in its level of procedural control, but it is even more explicit that the skills themselves must govern agent behavior. Representative files such as `using-superpowers`, `brainstorming`, `test-driven-development`, and `systematic-debugging` are full of hard gates:

- use a skill before acting
- do not write code before design approval
- do not write production code before a failing test
- do not propose fixes before root-cause analysis

This is helpful when:

- you want deterministic behavior from agents over long sessions
- you intend to use subagents heavily
- you need the workflow to survive weaker models or lower-context workers
- you do not trust informal reminders to hold under pressure

The downside is that the repo imposes strong assumptions about how work should happen. That increases overhead, creates more possible conflicts with local project instructions, and makes workflow-state bugs more important than they would be in a looser system.

## Planning and Specification

### Addy

Planning is document-first. The repo provides a clear progression from specification to task breakdown to build execution. The model is well suited to:

- front-loading requirements
- making acceptance criteria explicit
- forcing early human review
- keeping implementation tied to written artifacts

This is good when requirements are unstable or when agent work needs disciplined checkpoints before coding begins.

### Matt

Planning is system-first rather than document-first. `to-prd` and `to-issues` push toward issue-tracker-native decomposition, with vertical slices and explicit role distinctions such as human-in-the-loop and asynchronous review states. The repo expects that "work planning" should plug into the team's operating system, not sit in a disconnected markdown artifact.

This is stronger when the real unit of work is the issue, not the standalone plan doc.

### Superpowers

Planning is document-first, but far more operationally prescriptive than Addy's. `brainstorming` requires project-context exploration, one-question-at-a-time refinement, alternative approaches, design approval, spec writing, self-review, and then handoff to `writing-plans`. `writing-plans` then requires tiny 2-5 minute tasks with:

- exact file paths
- actual code blocks
- exact commands
- expected output
- explicit TDD steps

This is strongest when the plan must be executable by a weaker or lower-context agent without improvisation. It is weaker when the team already uses issue trackers as the primary unit of work or when such heavy plans would duplicate existing process.

## TDD and Verification

### Addy

Addy's TDD material is broader and more process-complete. It explicitly covers:

- failing test first
- test pyramid thinking
- mocking boundaries
- browser verification
- rationalizations agents use to avoid testing
- criteria for finishing work

This is more robust as a generalized team baseline. It is especially useful if the main problem is agents skipping verification or producing test theater.

### Matt

Matt's TDD material is more opinionated and tighter. Its emphasis is on:

- public contracts
- behavior over internals
- vertical tracer bullets
- incremental one-test-at-a-time loops
- checking with the human when the most important behaviors are unclear

This is better when the team already knows how to test but needs the agent to stop writing meaningless tests and stop decomposing work horizontally.

### Superpowers

Superpowers has the hardest-line testing doctrine of the three. Its TDD skill does not merely prefer test-first work; it treats deviations as workflow violations:

- code written before tests should be deleted
- test passes without failing first means the test is invalid
- manual verification is not a substitute
- bug fixes require failing tests

That is reinforced by adjacent skills. `systematic-debugging` forbids proposing fixes before root-cause analysis, and `verification-before-completion` exists specifically to stop agents from claiming success too early.

### Comparative view

If the question is "which repo gives safer default testing behavior across many users," Addy and Superpowers are the strongest, with Superpowers being more uncompromising and Addy being more broadly teachable.

If the question is "which repo is more likely to produce thoughtful behavioral tests in a mature codebase with a strong human operator," Matt is more interesting.

If the question is "which repo is most aggressive about preventing unsupported success claims," Superpowers is the clearest winner.

## Repository Awareness and Semantic Alignment

This is where Matt's repo is most differentiated.

`grill-with-docs`, `CONTEXT.md`, ADR integration, and the setup workflow are all aimed at creating a shared semantic layer between:

- the human's request
- the repository's existing vocabulary
- the architectural decisions already on record
- the issue tracker's workflow model

That is not a superficial feature. It directly addresses one of the hardest problems in agent-assisted engineering: the model can write locally correct code while misunderstanding what the project means by its own words.

Superpowers does require context exploration before brainstorming and plan writing, but its main alignment strategy is not domain-language capture. It aligns the agent by forcing explicit specs, exact file targets, and tightly scoped steps. That is useful, but it is not the same as teaching the agent the repository's conceptual vocabulary.

Addy's repo does not ignore repository context, but that is not its center of gravity either. Its center is engineering discipline, not semantic adaptation.

So in this dimension:

- Matt is strongest on semantic alignment
- Superpowers is stronger on operational alignment than semantic alignment
- Addy is primarily concerned with execution discipline

## Architecture and Codebase Health

Matt's repo is more explicitly concerned with preventing long-term architectural drift. The combination of:

- `zoom-out`
- `improve-codebase-architecture`
- domain language pressure
- issue decomposition pressure

creates a workflow that repeatedly asks whether the local change is worsening the larger system.

Superpowers cares about codebase health through a different mechanism:

- YAGNI and DRY are repeated throughout the workflow
- `writing-plans` pushes smaller, responsibility-focused files
- `systematic-debugging` explicitly says that 3+ failed fixes should trigger architectural questioning

That is a real architectural backstop, but it is still secondary to workflow control.

Addy's repo covers code quality and simplification, but more as one phase in the lifecycle rather than as a pervasive architectural stance.

That means:

- Addy is stronger on execution control
- Matt is stronger on architectural self-correction
- Superpowers is stronger on preventing implementation drift and context pollution during execution

## Multi-Agent and Orchestration Model

Addy and Superpowers are both strong here, but in different ways.

Addy's repo is stronger as an orchestration framework. Its slash commands and specialist personas provide explicit role boundaries, phase boundaries, synthesis points, and final decision rules. The `ship` flow is a good example of staged review-and-decision orchestration.

Superpowers is stronger as an autonomous implementation engine once a plan already exists. `subagent-driven-development` dispatches a fresh subagent per task, keeps session context isolated, inserts review after each task, and is designed for long continuous runs. `dispatching-parallel-agents` expands that model to independent tracks.

Matt's repo can participate in multi-agent workflows, but that is not where most of its design energy went. Its model is more "make one agent work like a good engineer in this repo" than "coordinate specialized agents across the whole delivery lifecycle."

A useful distinction is:

- Addy is better at phase-oriented orchestration
- Superpowers is better at task-oriented autonomous execution
- Matt is best understood as single-agent semantic guidance

## Tooling Portability

Superpowers now has the strongest visible harness-integration story of the three. Its README, Codex-specific docs, install guides, and release notes show active support work for:

- Claude Code
- Codex CLI
- Codex App
- Cursor
- OpenCode
- Gemini CLI
- GitHub Copilot CLI
- Factory Droid

It also maintains tool-mapping references and release-note history for harness-specific fixes, which is a sign that portability is not just conceptual but operational.

Addy also has a clear cross-platform story and broad packaging, but the visible recent investment in harness-specific adaptation appears stronger in Superpowers.

Matt's repo is more portable in principle than in operational documentation. The skills are plain text and the ideas are not tool-bound, but the actual value comes from adopting the surrounding repository patterns:

- setup skill
- issue tracker conventions
- `docs/agents/`
- `CONTEXT.md`
- ADR references

That is portable at the concept level, but less plug-and-play.

## Maintenance and Ecosystem Signals

As inspected on May 7, 2026:

- `obra/superpowers` showed by far the largest visible adoption and the most productized release surface
- `mattpocock/skills` showed strong developer mindshare relative to its smaller, concept-driven packaging
- `addyosmani/agent-skills` showed the clearest explicit framework structure and compatibility intent

The significance of that split is:

- Superpowers appears to have become a large operational ecosystem, not just a repo
- Matt's repo appears to punch above its packaging weight because the ideas are sharp and memorable
- Addy's repo appears to evolve as a disciplined framework layer with broader lifecycle framing than Matt and less plugin-product surface than Superpowers

Superpowers' release notes also make its maintenance style visible: there is sustained work on harness compatibility, worktree behavior, review-loop cost, bootstrap injection, and cross-platform execution details. That is a different maintenance profile from a mostly conceptual skill library.

## Failure Modes and Friction Seen in Issues

### Addy

Representative issue threads surfaced integration and control-surface problems:

- hook configuration mismatches
- upstream hook limitations in Claude Code
- slash-command collisions with built-in commands such as `/review`

These are normal symptoms of a repo that is acting like a framework layer on top of multiple host tools. The more integration surface area a system claims, the more it inherits compatibility friction.

### Matt

Representative issue threads surfaced behavior-control problems:

- planning skills drifting into implementation when they should stay in planning
- TDD workflows losing enough issue context that adjacent issue boundaries blur

These are normal symptoms of a repo that relies more on agent judgment and repo semantics than on hard procedural boundaries.

### Superpowers

Representative issue threads surfaced workflow-state and chain-coordination problems:

- spec and plan staleness when parallel sessions change the repo between brainstorming and execution
- lack of structured handoff when context fills during plan execution
- ambiguous skill or command naming causing incorrect invocation

These are normal symptoms of a system that tightly couples multiple phases into one intended workflow. The stronger the chain is, the more failures show up as state-management problems between stages rather than inside any single skill.

This contrast is important:

- Addy's problems are mostly integration and framework-edge problems
- Matt's problems are mostly alignment and execution-boundary problems
- Superpowers' problems are mostly workflow-state, handoff, and orchestration-assumption problems

## Where Each Repo Is Strongest

### Choose Addy when

- you want a standardized agent engineering process
- you need strong lifecycle coverage end to end
- you want safer defaults for testing, review, and shipping
- you care about phase-oriented multi-agent orchestration
- you need support across multiple agent environments
- your biggest concern is undisciplined agent execution

### Choose Matt when

- you want the agent to learn the repository's language and workflow
- issue tracker integration matters more than standalone plan artifacts
- you care deeply about architectural drift
- you want tighter human control and less framework overhead
- your repository has important domain terminology the agent must respect
- your biggest concern is semantic misalignment

### Choose Superpowers when

- you want the agent locked into a mandatory end-to-end workflow
- you plan to use subagents as a default execution mechanism
- you want explicit worktree isolation and execution handoff structure
- you need harness-specific installation and tool-mapping guidance
- you want strong protection against test skipping and unsupported completion claims
- your biggest concern is long-run execution drift

## Hybrid Adoption View

The three repos are compatible at the idea level but not cleanly compatible if installed wholesale without governance.

The cleanest pairings are selective:

- use Addy for outer lifecycle control and Matt for semantic alignment
- use Superpowers for execution discipline and Matt for repository language and architecture pressure

The highest-conflict pairing is Addy plus Superpowers, because both want to own the workflow spine.

The most valuable pieces to borrow from Matt into either Addy or Superpowers are:

- `CONTEXT.md`
- ADR-aware prompting
- `grill-with-docs`
- issue-tracker-native decomposition
- architecture review vocabulary

The most valuable pieces to borrow from Superpowers into either Addy or Matt are:

- bootstrap discipline around skill invocation
- explicit worktree isolation
- subagent-per-task execution loops
- verification-before-completion style gates
- detailed harness tool-mapping docs

The most valuable pieces to borrow from Addy into either Matt or Superpowers are:

- simpler lifecycle framing
- clearer phase terminology
- stronger top-level packaging of review and shipping concerns

What should not be combined casually:

- multiple meta-skills that all try to control skill invocation order
- multiple mandatory brainstorming and planning gates
- multiple overlapping TDD doctrines
- multiple overlapping review or finish/ship entry points
- multiple systems trying to own worktree or branch lifecycle

If more than one of these repos is used in one environment, command namespacing and precedence rules are required.

## Overall Judgment

`addyosmani/agent-skills` is the better repository if the goal is to establish a repeatable team-wide framework for agent-assisted software delivery. It is broad, structured, and intentionally lifecycle-shaped.

`mattpocock/skills` is the more interesting repository if the goal is to make agents behave like informed collaborators inside a specific codebase. Its best ideas are about language, architecture, and how the repository itself teaches the agent what "correct" means.

`obra/superpowers` is the better repository if the goal is to keep an agent inside an opinionated workflow long enough to produce reliable multi-step execution, especially when subagents and long autonomous runs are part of the operating model.

If forced to summarize the difference in one sentence:

- Addy provides a control plane for disciplined agent execution.
- Matt provides a semantic operating model for repo-aware agent collaboration.
- Superpowers provides a workflow runtime for execution-heavy agent autonomy.

## Sources

- <https://github.com/addyosmani/agent-skills>
- <https://github.com/mattpocock/skills>
- <https://github.com/obra/superpowers>
- <https://raw.githubusercontent.com/addyosmani/agent-skills/main/.claude-plugin/plugin.json>
- <https://raw.githubusercontent.com/addyosmani/agent-skills/main/skills/using-agent-skills/SKILL.md>
- <https://raw.githubusercontent.com/addyosmani/agent-skills/main/skills/spec-driven-development/SKILL.md>
- <https://raw.githubusercontent.com/addyosmani/agent-skills/main/.claude/commands/ship.md>
- <https://raw.githubusercontent.com/addyosmani/agent-skills/main/docs/skill-anatomy.md>
- <https://github.com/addyosmani/agent-skills/commits/main>
- <https://github.com/addyosmani/agent-skills/issues/110>
- <https://github.com/addyosmani/agent-skills/issues/95>
- <https://raw.githubusercontent.com/mattpocock/skills/main/CLAUDE.md>
- <https://raw.githubusercontent.com/mattpocock/skills/main/CONTEXT.md>
- <https://raw.githubusercontent.com/mattpocock/skills/main/skills/engineering/grill-with-docs/SKILL.md>
- <https://raw.githubusercontent.com/mattpocock/skills/main/skills/engineering/tdd/SKILL.md>
- <https://raw.githubusercontent.com/mattpocock/skills/main/skills/engineering/tdd/tests.md>
- <https://raw.githubusercontent.com/mattpocock/skills/main/skills/engineering/to-prd/SKILL.md>
- <https://raw.githubusercontent.com/mattpocock/skills/main/skills/engineering/setup-matt-pocock-skills/SKILL.md>
- <https://github.com/mattpocock/skills/commits/main>
- <https://github.com/mattpocock/skills/issues/134>
- <https://github.com/mattpocock/skills/issues/129>
- <https://raw.githubusercontent.com/obra/superpowers/main/README.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/docs/README.codex.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/.codex/INSTALL.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/skills/using-superpowers/SKILL.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/skills/brainstorming/SKILL.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-plans/SKILL.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/skills/subagent-driven-development/SKILL.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/skills/test-driven-development/SKILL.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/skills/systematic-debugging/SKILL.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/skills/verification-before-completion/SKILL.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/skills/using-git-worktrees/SKILL.md>
- <https://raw.githubusercontent.com/obra/superpowers/main/skills/requesting-code-review/SKILL.md>
- <https://github.com/obra/superpowers/releases>
- <https://github.com/obra/superpowers/blob/main/RELEASE-NOTES.md>
- <https://github.com/obra/superpowers/issues/989>
- <https://github.com/obra/superpowers/issues/1002>
- <https://github.com/obra/superpowers/issues/931>
