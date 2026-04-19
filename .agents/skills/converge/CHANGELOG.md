# Changelog

All notable changes to this skill are documented in this file.

This project follows Semantic Versioning.

## [1.0.1] - 2026-04-19

### Changed

- Added explicit verification-first sequencing policy to Judge and Inspector prompts.
- Added sequencing-audit fields to judge/inspector templates for round-level traceability.
- Updated quickstart and standards docs to gate implementation on red-baseline verification evidence.

## [1.0.0] - 2026-04-19

### Added

- Initial versioned release of the `converge` skill.
- Compact skill spec with stable role/boundary and loop-control contract.
- Round scaffolding automation via `scripts/scaffold_round.sh`.
- Quickstart runbook template at `templates/conductor_quickstart.template.md`.

### Changed

- `scripts/init_converge_session.sh` now scaffolds canonical round docs.
- `scripts/new_round.sh` now scaffolds canonical round docs.