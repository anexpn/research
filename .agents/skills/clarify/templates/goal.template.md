# Goal

## Objective



## Success Criteria

- id: C1
  - criterion: 
  - verification_type: <automated|agent|human|mixed>
  - expected_evidence: <test output, artifact path, or reviewer sign-off>
  - closure_signal: <what explicit signal marks this criterion closed; e.g., exact metric/threshold/report decision/sign-off field>
  - rubric: <required when criterion is subjective or human-judged; else none>
- id: C2
  - criterion: 
  - verification_type: <automated|agent|human|mixed>
  - expected_evidence: <test output, artifact path, or reviewer sign-off>
  - closure_signal: <what explicit signal marks this criterion closed; e.g., exact metric/threshold/report decision/sign-off field>
  - rubric: <required when criterion is subjective or human-judged; else none>

## Verification Spec Reference

- verification_spec_path: `verification_spec.md`
- note: `verification_spec.md` defines natural-language test scenarios and verification intent. Implementation of tests/prompts/guidance happens in converge rounds.

## Constraints

- <Performance, style, dependency, safety, runtime constraints>

## Non-goals

- 

## Round Limits

- max_implementation_rounds: 3
- max_verification_rounds: 2

## Human Verification

- required: <true|false>
- approver_role: <requester|reviewer|domain expert|none>
- evidence_format: <artifact links, screenshots, checklist, notes|none>
- completion_rule: <COMPLETE blocked until required human evidence exists|none>