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

- <Instruction 1 for next Builder round>
- <Instruction 2 for next Builder round>

## Completion evidence

- <If COMPLETE: tests/checks that prove success>

## Human gate check

- human_gate_status: <satisfied|pending>
- Evidence: