# Goal

## Objective

Create a single-script Python ray tracer that can render an image similar to `003-try-ray-tracing-1/data/spheres.png` in composition and visual quality, including basic ray tracing, anti-aliasing, gamma correction, depth of field, and material models (`lambertian`, `metal`, `glass`), runnable with `uv run --with ...`.

## Success Criteria

- id: C1
  - criterion: Required rendering features are implemented and active: basic ray tracing, anti-aliasing, gamma correction, depth of field camera blur, and materials (`lambertian`, `metal`, `glass`).
  - verification_type: mixed
  - expected_evidence: automated feature-check logs, per-round agent quality reports, and final human sign-off checklist.
  - closure_signal: all C1 automated feature assertions pass; agent per-round report marks no missing required feature; final human checklist marks "pass" for all required features.
  - rubric: human review rubric requires visible depth-of-field separation, plausible diffuse/metal/glass appearance differences, and no clearly broken shading artifacts.
- id: C2
  - criterion: Renderer exposes CLI args for `width`, `height`, `samples`, `seed`, and `output path`, and runs through `uv run --with` dependency invocation.
  - verification_type: automated
  - expected_evidence: command invocation logs, generated output files, and CLI behavior assertions.
  - closure_signal: scripted CLI checks pass for all required args (including failure behavior for invalid values) with expected exit codes and artifacts.
  - rubric: none
- id: C3
  - criterion: Final render matches the reference image target profile (same resolution/settings as reference expectation) and clears strict image-similarity gates.
  - verification_type: mixed
  - expected_evidence: similarity report artifact against `data/spheres.png`, per-round agent comparison notes, and final human visual sign-off.
  - closure_signal: automated metrics satisfy SSIM `>= 0.85` and color-histogram distance `<= 0.12`; agent final-round assessment marks composition/material quality acceptable; human final review is approved.
  - rubric: human review rubric checks scene layout similarity (camera angle, large foreground spheres, background sphere band), material plausibility, and overall visual parity.
- id: C4
  - criterion: Fixed-seed renders are statistically reproducible across repeated runs (near-identical metrics, not byte-identical requirement).
  - verification_type: automated
  - expected_evidence: repeated-run reproducibility report with run-to-run similarity metrics and tolerance checks.
  - closure_signal: same-seed repeated runs satisfy reproducibility thresholds defined in `verification_spec.md`; different-seed control run triggers expected non-zero divergence signal.
  - rubric: none

## Verification Spec Reference

- verification_spec_path: `verification_spec.md`
- note: `verification_spec.md` defines natural-language test scenarios and verification intent. Implementation of tests/prompts/guidance happens in converge rounds.

## Constraints

- Single-script Python implementation.
- Dependency execution must use `uv run --with ...`.
- `numpy`, `Pillow`, and additional dependencies are allowed as needed.
- Render target should follow the same resolution/settings profile as the reference image request.

## Non-goals

- No additional explicit non-goals beyond implied project scope.

## Round Limits

- max_implementation_rounds: 10
- max_verification_rounds: 3

## Human Verification

- required: true
- approver_role: requester
- evidence_format: final checklist plus artifact links to output image and similarity report.
- completion_rule: COMPLETE is blocked until final human approval evidence is recorded for C1/C3.