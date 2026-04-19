# Builder Report

## Round

## Round Intent

<build_verification_artifacts|implement_solution|final_gate>

## Plan for this round

- carry_forward_bundle_consumed: <yes|partial|no>
- backlog_ids_executed:
  - 
  - 
- protected_scope_respected: <yes|not_applicable|no>
- plan_deviation_reason: 
- <Targeted change 1>
- <Targeted change 2>

## Changes made

- File: `<path>` -

## Verification artifacts

- automated_checks:
  - <stable project test/script path(s) created/updated, or none>
- agent_checks:
  - <stable project prompt/spec path(s) created/updated, or none>
- human_checks:
  - <stable project guidance/checklist path(s) created/updated, or none>

## Evidence artifacts (canonical in round folder)

- run_dir: `<round_path>/run/`
- artifacts:
  - source_path: `<original generated artifact path>`
  canonical_path: `<round_path>/run/<artifact-name>`
  criterion_or_check: `<criterion id or check name>`
  - source_path: `<original generated artifact path>`
  canonical_path: `<round_path>/run/<artifact-name>`
  criterion_or_check: `<criterion id or check name>`
- stable_source_artifacts_not_snapshotted:
  - `<unchanged test/prompt/checklist/spec paths intentionally referenced in-place, or none>`
- source_artifact_snapshots_in_run:
  - source_path: `<stable project artifact path>`
  canonical_path: `<round_path>/run/<snapshot-path>`
  reason: `<changed_this_round|immutable_audit|required_by_policy>`
- duplicate_files_outside_run:
  - `<none OR file names found in both round root and run with remediation>`
- assertion_strength_notes:
  - `<scenario/check id -> meaningful assertion used (threshold/tolerance/comparator/etc)>`

## Commands executed

```bash
# Include exact commands run
```

## Evidence

```text
# Paste raw test/build/runtime output snippets
```

## Status

- objective_progress: <met|partial|not_met>
- blocker_detected: <true|false>
- blocker_details:

