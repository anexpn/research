# Inspector Review

## Round

## Round Intent

## Standards consulted

- `.agents/standards/quality_gate.md`
- `.agents/standards/reference_good/...`
- `.agents/standards/reference_bad/...`

## Findings

### Finding

- severity: <high|medium|low>
- criterion_id: 
- claim: 
- evidence: <logs/diff/reference path>
- expected standard: <which rule/reference was violated>
- action_for_builder: <concrete next step; command, file path, or artifact to produce>
- suggested_automated_check: <specific command/script or none>
- ambiguity_note: <none OR what is vague and a proposed criterion rewrite/user clarification>
- novelty_check:

## Verdict

- blocking_findings: 
- non_blocking_findings: 
- unresolved_ambiguities: 
- requires_goal_amendment: <true|false>

## Evidence artifact audit

- artifact_copy_compliance: <pass|fail>
- missing_or_unverifiable_artifacts:
  - <artifact expected in round evidence folder but missing/unreadable>
- provenance_mismatches:
  - <source path / copied path mismatch or unclear mapping>

## Criterion tokens

- criterion_id: C1
  - automated: <pass|fail|not_applicable>
  - agent: <pass|fail|not_applicable>
  - human: <pass|fail|not_applicable|pending>
  - overall: <pass|fail|pending>
- criterion_id: C2
  - automated: <pass|fail|not_applicable>
  - agent: <pass|fail|not_applicable>
  - human: <pass|fail|not_applicable|pending>
  - overall: <pass|fail|pending>

## Intent checks

- build_verification_artifacts: <pass|fail|not_applicable>
- implement_solution: <pass|fail|not_applicable>
- final_gate: <pass|fail|not_applicable>