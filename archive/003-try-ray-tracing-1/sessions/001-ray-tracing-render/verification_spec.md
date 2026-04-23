# Verification Spec

## Purpose

Define criterion-level verification intent in natural language. This file does not contain test code.

## Gate Timing Default

- default_gate_timing: per_round

## Criterion Verification Map

- criterion_id: C1
  - verification_type: mixed
  - gate_timing: per_round
  - scenario_bdd:
    - scenario_id: C1-S1-feature-activation
      - given: renderer is executed with fixed parameters that enable all required features and writes an output image.
      - when: automated checks compute feature-sensitive contrast/comparison metrics against controlled toggles or baselines.
      - then: anti-aliasing, gamma correction, and depth-of-field effects each produce measurable, expected directional changes, and material outputs remain numerically distinct in sampled regions.
      - assertion_contract:
        - metric_or_property: AA edge variance reduction, DOF focus-vs-defocus sharpness delta, gamma-correct luminance distribution, and material-region reflectance/transmission separability.
        - oracle_source: test_owned
        - comparator: ordered_greater
        - target_or_bound: required deltas exceed configured minimum bounds in test fixtures.
        - tolerance: bounded numeric tolerance defined in the verification harness for repeatability.
        - deterministic_setup: fixed scene parameters and seed for all baseline/contrast renders.
        - regression_trap: rerender with one feature disabled must violate at least one corresponding metric bound.
  - automated_check_intent: implement script-level checks that compare full-feature render against controlled baselines/toggles and fail if expected directional feature effects are missing.
  - agent_check_intent: per round, inspect generated image(s) for obvious artifact regressions and confirm visible manifestation of required features in natural-language notes.
  - human_check_guidance_intent: final reviewer checklist must confirm visible DOF separation and distinct lambertian/metal/glass appearance characteristics.
  - expected_evidence:
    - automated: feature-check logs and metric summary artifact.
    - agent: per-round image quality report notes.
    - human: final review checklist entry.
- criterion_id: C2
  - verification_type: automated
  - gate_timing: per_round
  - scenario_bdd:
    - scenario_id: C2-S1-cli-contract
      - given: script is invoked via `uv run --with ...` with each required CLI argument.
      - when: executions vary `width`, `height`, `samples`, `seed`, and `output path`.
      - then: output image dimensions and artifacts match requested values; invalid input cases fail with non-zero exit status and explanatory error text.
      - assertion_contract:
        - metric_or_property: CLI argument behavior, output file existence, dimensions equality, and exit-code contract.
        - oracle_source: test_owned
        - comparator: ==
        - target_or_bound: all required arguments are honored exactly and invalid cases fail as expected.
        - tolerance: none
        - deterministic_setup: fixed command templates and temporary output paths.
        - regression_trap: omit or corrupt one required arg and assert failure rather than silent fallback.
  - automated_check_intent: maintain command-level tests validating positive and negative CLI paths with explicit assertions on dimensions and exit behavior.
  - agent_check_intent: none
  - human_check_guidance_intent: none
  - expected_evidence:
    - automated: CLI verification logs and generated output metadata.
    - agent: none
    - human: none
- criterion_id: C3
  - verification_type: mixed
  - gate_timing: final_only
  - scenario_bdd:
    - scenario_id: C3-S1-reference-similarity
      - given: final render and reference image `003-try-ray-tracing-1/data/spheres.png`.
      - when: automated similarity evaluation computes SSIM and color-histogram distance on aligned images.
      - then: SSIM is at least `0.85` and color-histogram distance is at most `0.12`.
      - assertion_contract:
        - metric_or_property: structural similarity (SSIM) and color histogram distance.
        - oracle_source: test_owned
        - comparator: >=
        - target_or_bound: SSIM `>= 0.85`; histogram distance bound checked with `<= 0.12`.
        - tolerance: numeric tolerance only for metric implementation precision, not threshold relaxation.
        - deterministic_setup: fixed render settings and seed for final gated comparison.
        - regression_trap: intentionally low-quality render (reduced samples/AA or wrong scene parameters) must fail one or both thresholds.
  - automated_check_intent: produce a machine-readable similarity report and fail the gate when either strict threshold is not met.
  - agent_check_intent: each round, compare intermediate output with reference for composition/layout drift and material plausibility, documenting gaps before final gate.
  - human_check_guidance_intent: final reviewer confirms scene resemblance in composition, camera framing, material feel, and overall quality against reference.
  - expected_evidence:
    - automated: final similarity metric report artifact.
    - agent: per-round comparison notes and final-round recommendation.
    - human: final human approval checklist artifact.
- criterion_id: C4
  - verification_type: automated
  - gate_timing: per_round
  - scenario_bdd:
    - scenario_id: C4-S1-seed-reproducibility
      - given: identical parameters and identical seed across repeated renders.
      - when: run A and run B are compared using inter-run image similarity metrics.
      - then: same-seed runs satisfy tight reproducibility bounds, while a different-seed contrast run demonstrates measurable divergence.
      - assertion_contract:
        - metric_or_property: inter-run SSIM and histogram distance for same-seed and different-seed pairs.
        - oracle_source: test_owned
        - comparator: within_epsilon
        - target_or_bound: same-seed metrics remain within configured epsilon band; different-seed pair exceeds minimum divergence floor.
        - tolerance: epsilon values defined in automated harness to permit statistical-noise-level drift only.
        - deterministic_setup: fixed scene settings and fixed runtime environment assumptions.
        - regression_trap: if same-seed divergence exceeds epsilon or different-seed divergence is indistinguishable, fail.
  - automated_check_intent: enforce reproducibility with bounded statistical tolerance and a contrast condition to detect false determinism checks.
  - agent_check_intent: none
  - human_check_guidance_intent: none
  - expected_evidence:
    - automated: reproducibility metrics report across repeated runs.
    - agent: none
    - human: none

## Automated scenario quality bar

For automated scenarios, "then" statements must be falsifiable and measurable.
Do not use only:

- symbol/module presence checks,
- non-`None` checks,
- "works"/"looks right"/"changes consistently" language without thresholds.