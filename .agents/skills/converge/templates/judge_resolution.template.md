# Judge Resolution

## Round

## Round Intent

status: <COMPLETE|CONTINUE|READY_FOR_HUMAN>
blocker_detected: <true|false>
primary_unmet_criterion: 
human_verification_required: <true|false>
human_verification_evidence: <path(s) or none>

## Orchestration summary

- builder_inputs:
- inspector_scope:

## Evidence artifact routing

- evidence_dir: `<round_path>/evidence/`
- copied_artifacts:
  - <artifact copied path and purpose>
- missing_copies:
  - <artifact that should have been copied but was not>

## Round memory

- strengths_to_preserve:
- regressions_detected:
- next_priority_deltas:

## Carry-forward bundle (for next Builder)

- required_core:
  - open_criteria:
  - criterion_id: <C#>
    failure_reason: <why still failing/pending>
    evidence_path: <path proving current state>
  - ordered_delta_backlog:
  - id: D1
    priority: P1
    action: <concrete action for Builder>
    done_condition: <observable stop condition>
  - id: D2
    priority: P2
    action: <concrete action for Builder>
    done_condition: <observable stop condition>
- optional_enrichments:
  - locked_scope:
    - <files/areas that should not regress (optional)>
  - do_not_touch:
    - <explicit no-edit boundaries (optional)>
  - accepted_evidence_reuse:
    - <prior evidence path that remains valid (optional)>
  - invalidated_evidence:
    - <prior evidence path no longer valid and why (optional)>
  - risk_watchlist:
    - <high-risk regression to re-check next round (optional)>
  - environment_notes:
    - <tooling/environment assumption or limitation (optional)>
  - needs_user_clarification:
    - <none OR exact unresolved question>

## Accepted findings

- <finding id + reason>

## Overruled findings

- <finding id + evidence-backed rationale>

## Decision rationale

## Loop control rationale

- 

- 

- 

## Delta instructions

- [D1] <Instruction 1 for next Builder round>
- [D2] <Instruction 2 for next Builder round>
- <If no backlog IDs were created, provide ordered plain instructions instead>

## Completion evidence

- <If COMPLETE: tests/checks that prove success>

## Human gate check

- human_gate_status: <satisfied|pending>
- Evidence: