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
    - scenario_id: 
      - given:
      - when:
      - then:
      - assertion_contract:
        - metric_or_property: 
        - oracle_source: <test_owned|implementation_owned|external_tool>
        - comparator: <==|!=|<=|>=|within_epsilon|ordered_less|ordered_greater>
        - target_or_bound: 
        - tolerance: 
        - deterministic_setup: <seed/fixed fixture/command stability requirement or none>
        - regression_trap: <negative/contrast condition that should fail on regression>
  - automated_check_intent: <natural-language description of required tests/scripts or none>
  - agent_check_intent: 
  - human_check_guidance_intent: <what guidance/checklist must exist for a human reviewer or none>
  - expected_evidence:
    - automated: <test log path(s) or none>
    - agent: <agent report path(s) or none>
    - human: <human verification file path(s) or none>
- criterion_id: C2
  - verification_type: <automated|agent|human|mixed>
  - gate_timing: <per_round|final_only>
  - scenario_bdd:
    - scenario_id: 
      - given:
      - when:
      - then:
      - assertion_contract:
        - metric_or_property: 
        - oracle_source: <test_owned|implementation_owned|external_tool>
        - comparator: <==|!=|<=|>=|within_epsilon|ordered_less|ordered_greater>
        - target_or_bound: 
        - tolerance: 
        - deterministic_setup: <seed/fixed fixture/command stability requirement or none>
        - regression_trap: <negative/contrast condition that should fail on regression>
  - automated_check_intent: <natural-language description of required tests/scripts or none>
  - agent_check_intent: 
  - human_check_guidance_intent: <what guidance/checklist must exist for a human reviewer or none>
  - expected_evidence:
    - automated: <test log path(s) or none>
    - agent: <agent report path(s) or none>
    - human: <human verification file path(s) or none>

## Automated scenario quality bar

For automated scenarios, "then" statements must be falsifiable and measurable.
Do not use only:

- symbol/module presence checks,
- non-`None` checks,
- "works"/"looks right"/"changes consistently" language without thresholds.