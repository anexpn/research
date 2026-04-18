# Verification Spec

## Purpose

Define criterion-level verification intent in natural language. This file does not contain test code.

## Gate Timing Default

- default_gate_timing: <per_round|final_only>

## Criterion Verification Map

- criterion_id: C1
  - verification_type: <automated|agent|human|mixed>
  - gate_timing: <per_round|final_only>
  - scenario_bdd:
    - given:
    - when:
    - then:
  - automated_check_intent: <natural-language description of required tests/scripts or none>
  - agent_check_intent: <natural-language description of prompt-based check and rubric or none>
  - human_check_guidance_intent: <what guidance/checklist must exist for a human reviewer or none>
  - expected_evidence:
    - automated: <test log path(s) or none>
    - agent: <agent report path(s) or none>
    - human: <human verification file path(s) or none>

- criterion_id: C2
  - verification_type: <automated|agent|human|mixed>
  - gate_timing: <per_round|final_only>
  - scenario_bdd:
    - given:
    - when:
    - then:
  - automated_check_intent: <natural-language description of required tests/scripts or none>
  - agent_check_intent: <natural-language description of prompt-based check and rubric or none>
  - human_check_guidance_intent: <what guidance/checklist must exist for a human reviewer or none>
  - expected_evidence:
    - automated: <test log path(s) or none>
    - agent: <agent report path(s) or none>
    - human: <human verification file path(s) or none>
