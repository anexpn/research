# Evaluation Task Extraction Methodology

## Context

We need development tasks that evaluate coding agents on realistic software work, not only toy prompts or hand-invented scenarios. A useful benchmark should exercise how agents read existing code, infer intent, preserve compatibility, write tests, debug regressions, implement features, and make trade-offs under incomplete information.

Thinking evaluation tasks out of thin air is not practical. Public issue-based benchmarks such as SWE-bench are useful, but they are biased toward popular open-source projects where issues, pull requests, reproduction steps, and maintainer discussion are often better framed than work inside enterprise projects. Enterprise work often starts from less complete requirements, partial QA evidence, informal context, and a codebase whose environment may be difficult to reproduce.

The better target is a reusable methodology for extracting evaluation tasks from real verified development changes in any repository, public or private. The methodology should turn repository history and supporting evidence into self-contained task capsules that can be run repeatedly against different agents.

## Goals

- Define a repeatable method for creating development-evaluation tasks from real repository changes.
- Support multiple task types: bug fixes, feature implementation, refactoring, test writing, migration, performance work, observability, and compatibility changes.
- Package each task with the pre-change repository snapshot and the environment setup needed to run it.
- Treat the accepted post-change snapshot as evidence, not as a perfect golden answer.
- Make verifier construction a first-class part of the methodology because real acceptance tests are often incomplete, manual, flaky, or tied to private infrastructure.
- Support both public open-source and private enterprise operating modes.
- Attach a small set of meaningful tags so tasks can be sampled, compared, and analyzed.
- Enable scoring beyond pass/fail so partial progress and development quality can be compared.

## Non-Goals

- Do not build the full benchmark runner in this idea document.
- Do not define a fixed public corpus as the only valid benchmark.
- Do not require private production code to use the methodology.
- Do not assume the landed patch is the only correct implementation.
- Do not require live external services during evaluation.
- Do not rely on subjective human taste as the primary score.
- Do not create tasks that are mainly trivia, algorithm puzzles, or greenfield demos.

## Recommended Approach

Build a methodology-first "task factory" that can ingest repository history and produce task capsules from real landed changes. The same process should work in two modes:

- Public mode: use open-source repositories and public artifacts such as commits, pull requests, issues, tests, release notes, and review comments. This mode is reproducible and useful for calibration, but it should not be treated as fully representative of enterprise development.
- Enterprise mode: use private repository history, internal requirements, QA notes, incidents, screenshots, logs, and verified test suites. This mode is more realistic for internal evaluation, but it needs stronger controls for privacy, secrets, licenses, dependencies, and infrastructure.

The output is not a single large challenge. It is a collection of medium-sized task capsules, each derived from a real change and packaged with enough environment, evidence, verifier, and scoring metadata to run independently.

## Alternative Approaches

### Hand-Authored Benchmark Pack

Invent realistic task repositories by writing requirements, flawed designs, starter code, visible tests, hidden tests, and scoring rubrics from scratch.

Trade-off: This gives full control over difficulty and scoring, but it does not scale well. It also risks encoding the authors' idea of development work rather than the messy shape of real work.

### Public Open-Source Extraction Only

Extract tasks only from public repositories, using commit and pull-request history instead of relying only on issue descriptions.

Trade-off: This is easier to share and reproduce, but it still inherits public-project bias. Popular open-source issues often have clearer framing, stronger reproduction details, and different review norms than enterprise work.

### Enterprise Shadow Benchmark Only

Extract tasks primarily from private enterprise repositories and use them for internal evaluation.

Trade-off: This gives the strongest realism, but the resulting corpus is hard to share or externally audit. It also needs careful handling of secrets, licenses, internal dependencies, and proprietary context.

## Task Capsule

A task capsule is the unit of the methodology. It should contain:

```text
task/
  README.md                  # agent-facing task context
  prompt.md                  # exact instruction given to the agent
  task.json                  # task identity, source metadata, and tags
  scorer.md                  # human-readable scoring rubric
  scorer.json                # machine-readable scoring categories
  provenance.md              # source evidence and authoring decisions
  environment.md             # runtime, setup, services, and known caveats
  pre-change/                # repository snapshot before the target change
  reference-change/          # accepted change as evidence, not an oracle
  verifier/                  # visible tests, hidden tests, fixtures, scripts
  fixtures/                  # input data, screenshots, traces, exports, logs
```

The capsule should be self-contained enough that an evaluator can install dependencies, run the baseline tests, apply an agent's solution, and score the result without asking the original team for missing context.

## Task Types

The methodology should not overfit to bug fixes. Real development skill includes several change shapes:

- Bug fix: repair incorrect behavior, regressions, crashes, or edge cases.
- Feature: implement new product or platform behavior while fitting the existing codebase.
- Refactor: improve structure, remove duplication, or change internal boundaries while preserving behavior.
- Test writing: add meaningful coverage for an under-tested behavior, regression, or contract.
- Migration: move data, APIs, schemas, framework versions, or internal conventions safely.
- Performance: reduce runtime, memory, latency, or resource use while preserving output.
- Observability: improve logs, metrics, traces, alerts, or debugging surfaces.
- Compatibility: evolve behavior while preserving old clients, data formats, workflows, or APIs.

The extraction pipeline should classify the task type early because the verifier and scoring model depend on it.

## Extraction Pipeline

1. Discover candidate changes.
   - Search repository history for merged commits, pull requests, release branches, QA-verified fixes, migrations, refactors, test additions, and performance work.
   - Prefer changes with enough evidence to reconstruct intent and enough executable surface to verify behavior.

2. Classify the task.
   - Assign the task type, code area, approximate change size, and expected difficulty.
   - Reject changes that are mostly mechanical churn, pure formatting, dependency bumps without behavioral signal, or impossible to verify locally.

3. Reconstruct the requirement.
   - Use commit messages, PR text, issue discussion, design notes, QA notes, incident reports, screenshots, logs, and tests.
   - Write an agent-facing prompt that describes the desired outcome without copying the exact implementation path from the reference change.
   - Preserve ambiguity only when it reflects realistic work and the verifier can still distinguish good solutions from bad ones.

4. Prepare the pre-change snapshot.
   - Freeze the repository before the target change.
   - Capture dependency versions, runtime versions, setup commands, required services, seed data, environment variables, and local fixtures.
   - Confirm that the baseline test suites pass on the pre-change snapshot except for tests intentionally marked as task-relevant failures.

5. Preserve the reference change.
   - Store the accepted patch or post-change snapshot as evidence of one solution.
   - Use it to understand intent, affected areas, edge cases, and likely acceptance criteria.
   - Do not score by textual similarity to the reference change.

6. Build and harden the verifier bundle.
   - Preserve existing visible tests and QA checks.
   - Convert manual QA steps into automated tests when practical.
   - Add characterization tests for existing behavior that must remain stable.
   - Add hidden checks for edge cases, compatibility, and regressions inferred from the evidence.
   - Document acceptance criteria that cannot be automated.

7. Package and sanitize.
   - Remove secrets, credentials, customer data, private endpoints, and internal-only references that are not needed for the task.
   - Replace external services with local fakes, containers, fixtures, or documented exclusions.
   - Check licenses before redistributing public or private derived tasks.

8. Baseline-run the task.
   - Run setup from a clean checkout.
   - Verify that baseline tests are green.
   - Run at least one baseline agent or human pass to identify missing context, verifier gaps, and accidental shortcuts.

9. Finalize metadata and scoring.
   - Fill in task tags and scorer metadata.
   - Record known limitations in `provenance.md` and `environment.md`.

## Environment Reproducibility Gate

Repository history alone is not enough. A candidate task should not enter the corpus unless its pre-change snapshot can be paired with a reproducible environment.

The baseline gate is:

- dependencies install from captured lockfiles, local caches, mirrors, or documented package sources;
- runtime versions and system dependencies are recorded;
- setup commands can be run from a clean checkout;
- required services are local, mocked, containerized, or explicitly excluded from scoring;
- seed data and required environment variables are provided without secrets;
- the current test suites are green before task work begins, except tests intentionally marked as known task failures;
- flaky tests are stabilized, quarantined, or excluded from scoring with a written reason.

Enterprise repositories need extra care because old commits may depend on retired infrastructure, private registries, manual database state, or employee-local setup. Resolving those constraints is part of task authoring, not an evaluator responsibility.

## Evidence Model

Task authors should use multiple evidence sources rather than relying on one issue or one commit message:

- commit messages and diffs;
- pull request descriptions and review comments;
- linked issues, tickets, or incident reports;
- product requirements and design documents;
- QA notes, test plans, and manual verification steps;
- existing tests, fixtures, snapshots, and golden files;
- screenshots, recordings, logs, traces, metrics, and exported data;
- release notes or migration notes.

Evidence quality varies. The authoring process should state which sources were used and where the prompt or verifier required inference.

## Reference-Change Policy

The accepted post-change snapshot is not a golden standard. It may pass the team's QA cases without being fully functional, maintainable, or high quality.

Use the reference change as:

- evidence of intent;
- a clue for affected modules and edge cases;
- a source for expected outputs, fixtures, or tests;
- a baseline for approximate change size and difficulty;
- a comparison point for reviewer analysis.

Do not use it as:

- the only valid solution;
- a byte-for-byte oracle;
- proof that all behavior is correct;
- proof that all quality concerns were solved.

Scoring should evaluate the submitted solution against reconstructed requirements, verifier evidence, compatibility expectations, and maintainability criteria.

## Verifier Construction

Verifier construction is the bottleneck. Real acceptance checks are often incomplete, partly manual, flaky, or coupled to private infrastructure. A strong methodology must make verifier work explicit.

The verifier bundle should include:

- visible tests that help agents understand the main workflow;
- hidden tests that check edge cases, compatibility, and regressions;
- fixtures such as input data, snapshots, logs, screenshots, traces, and exported reports;
- setup and scoring scripts;
- manual-review notes for criteria that cannot be automated.

Verifier hardening should follow these rules:

- automate existing QA steps when the cost is reasonable;
- prefer behavior and contract checks over implementation-shape checks;
- include characterization tests for old behavior that must remain stable;
- avoid hidden tests that require guessing unstated facts;
- record known gaps when acceptance cannot be fully automated;
- reject tasks whose important success criteria cannot be verified at all.

For visual tasks, use screenshots and DOM or accessibility checks carefully. Prefer stable layout facts, element presence, dimensions, contrast, and interaction states over brittle whole-page pixel equality.

## Task Tags

Each task should include a small set of structured tags in `task.json`:

```json
{
  "id": "billing-tiered-discount-migration",
  "task_type": "migration",
  "difficulty": "hard",
  "change_size": "medium",
  "code_area": "backend",
  "acceptance_coverage": "medium"
}
```

Use only these required tags:

- `task_type`: `bug_fix`, `feature`, `refactor`, `test_writing`, `migration`, `performance`, `observability`, or `compatibility`.
- `difficulty`: `easy`, `medium`, `hard`, or `frontier`.
- `change_size`: `small`, `medium`, `large`, or `cross_cutting`.
- `code_area`: `frontend`, `backend`, `data`, `infra`, `cli`, `api`, `build`, or `docs`.
- `acceptance_coverage`: `low`, `medium`, or `high`.

Assign tags with these rules:

- `task_type` should describe the main skill being evaluated, even if the historical change mixed several kinds of work.
- `difficulty` should estimate how hard the task is for a strong coding agent under the benchmark time budget, not how hard it was for the original team.
- `change_size` should reflect the expected solution scope: `small` for localized edits, `medium` for several related files, `large` for broad module work, and `cross_cutting` for changes that span multiple layers or contracts.
- `code_area` should name the dominant area touched by the task. If several areas are equally important, choose the area that carries the main acceptance risk.
- `acceptance_coverage` should describe how much of the intended behavior is checked by automated or structured verifiers: `high` for most important criteria, `medium` for the main path plus some edge cases, and `low` for partial checks with important manual or inferred criteria remaining.

Other observations, such as ambiguity, verifier confidence, environment complexity, source mode, and reference quality, should be written in prose in `provenance.md` or `environment.md` instead of becoming required tags.

## Scoring Model

Use a 100 point score for each task, adapted by task type:

- 40 points: functional correctness from visible tests, hidden tests, fixtures, contracts, or structured output checks.
- 20 points: integration quality, including compatibility with existing APIs, data formats, workflows, and architecture.
- 15 points: test quality, focused on meaningful regression or contract coverage rather than raw test count.
- 15 points: maintainability, including small coherent changes, local style, readable design, and avoiding unnecessary rewrites.
- 10 points: operational quality, including performance, error handling, accessibility, observability, migration safety, or reproducibility depending on the task.

Written explanation can be checked for honesty and useful handoff notes, but it should not replace code and verifier outcomes. If it is scored, keep it as a small bonus outside the 100 point core score.

## Bias And Realism Controls

The corpus should avoid becoming a collection of unusually neat tasks.

Include:

- tasks with incomplete but usable requirements;
- changes where the right answer requires reading code and tests, not only prompt text;
- tasks across several code areas and change sizes;
- tasks where old behavior must be preserved;
- tasks where existing tests reveal only part of the issue;
- tasks with realistic setup and dependency friction that has been packaged for evaluation.

Avoid:

- tasks whose solution is obvious from one failing unit test;
- changes that are mostly formatting or dependency churn;
- tasks that depend on private knowledge not present in the capsule;
- tasks where hidden tests enforce arbitrary implementation details;
- tasks that require live external services;
- tasks that cannot be scored beyond subjective judgment.

## Supporting Materials

The methodology should be backed by reusable materials:

- candidate-discovery scripts for scanning commit history and pull requests;
- environment-capture scripts for recording runtimes, dependency locks, setup commands, services, and baseline test status;
- task-packaging scripts for creating the capsule layout;
- sanitizer scripts for secrets, customer data, private endpoints, and internal identifiers;
- verifier templates for visible tests, hidden tests, fixtures, and scoring scripts;
- authoring skills or prompts for candidate triage, requirement reconstruction, verifier hardening, and review;
- prompt-writing guidance for reconstructing task requirements without leaking the reference implementation;
- authoring checklists for evidence quality, environment reproducibility, verifier coverage, and bias controls;
- scorer schemas for `task.json` and `scorer.json`;
- reviewer guidance for judging maintainability, integration quality, and non-automated acceptance criteria.

These materials are part of the product. Without them, the methodology will depend too much on individual task authors.

## Constraints And Resolutions

Private code and secrets:

- sanitize secrets and customer data before packaging;
- keep enterprise capsules private when licensing or confidentiality requires it;
- replace proprietary endpoints with local fakes or fixtures.

Environment drift:

- capture runtime versions, dependency locks, setup commands, and required services;
- containerize or script local dependencies when practical;
- reject candidates that cannot be made reproducible at reasonable cost.

Incomplete acceptance tests:

- preserve existing tests, then harden with targeted hidden checks and characterization tests;
- document manual or unverifiable criteria;
- reject tasks where the main success condition cannot be checked.

Flaky tests:

- identify flakiness during baseline runs;
- stabilize, quarantine, or exclude flaky checks from scoring;
- record the decision in `environment.md`.

Reference-change quality:

- treat the landed change as evidence, not as the oracle;
- allow better solutions than the historical patch;
- score against requirements and verifiers.

Open-source bias:

- use public tasks for reproducible calibration;
- use private enterprise tasks when evaluating enterprise realism;
- report source mode and corpus composition in benchmark results.

## Baseline Evaluation Policy

Use these defaults for a first pilot:

- Prompt mode: closed benchmark prompts. The agent may write assumptions in its final answer, but the evaluator does not answer clarifying questions during the run.
- Scored output: repository changes are primary. Written explanation can receive at most a small bonus.
- Time budget: start with a 2 hour wall-clock cap per task and record intermediate checkpoints at 30, 60, and 120 minutes.
- Tool budget: allow normal local development tools, tests, formatters, and browsers. Disallow live external services unless the task provides a local fake.
- Hidden tests: keep exact hidden tests private, but describe hidden-test categories in `scorer.md` so agents are rewarded for robust engineering rather than guessing.
- Environment baseline: require a clean setup and green baseline test run before accepting the task into the corpus.

## Initial Pilot

Start with a small pilot rather than a large corpus:

1. Select 5 to 10 real changes from one public repository and package them with the methodology.
2. Select 5 to 10 real changes from one enterprise or private repository if available.
3. Cover at least four task types across the pilot, including one non-bug-fix task.
4. Require each task to pass the environment reproducibility gate.
5. Run a baseline agent and record failure modes, verifier gaps, setup friction, and scoring ambiguity.
6. Revise the supporting scripts, checklists, and templates before scaling the corpus.

The success criterion for the pilot is not a high task count. It is whether independent authors can use the methodology to produce capsules that are reproducible, realistic, scorable, and not overly shaped by issue descriptions or historical patch details.
