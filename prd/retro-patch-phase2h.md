# Retro Patch: Phase 2h — ci-hardening
Generated: 2026-03-22T00:00:00Z

## Suggested additions to CLAUDE.md (LEARNINGS section)

### New patterns discovered this sprint

- **Bitnami subchart PDB pattern**: When a bitnami/upstream subchart provides PDB by default,
  the review ceremony will still fail an AC like "charts/keycloak/templates/poddisruptionbudget.yaml exists".
  Always add a wrapper-level `templates/poddisruptionbudget.yaml`, and disable the upstream PDB via
  `<subchart>.pdb.create: false` in the parent values.yaml to avoid duplicate PDBs for the same selector.
  Example: `keycloak.pdb.create: false` in charts/keycloak/values.yaml.

- **Review ceremony AC "file X exists" is literal**: Even if the functional requirement is met via
  a subchart or upstream chart, the acceptance criterion file check requires the file to actually exist
  in the wrapper chart's templates directory.

- **Dynamic GH Actions matrix**: Use a `discover-charts` job with `outputs:` then
  `matrix: ${{ fromJson(needs.discover-charts.outputs.charts) }}`. Never hardcode chart lists.

- **shellcheck -S error on CI**: Ubuntu 24.04 uses shellcheck 0.10.0 which treats SC2002 as error;
  macOS homebrew has 0.11.0 (more lenient). Use `shellcheck -S error` to match CI behavior locally.

- **Bootstrap helper scripts placement**: Scripts in `bootstrap/providers/` are checked by CI's
  bootstrap-validate for node loop logic. API helper libraries belong in `bootstrap/frontdoor/` or
  a dedicated helpers dir, not in providers/.

## Stories that failed review (re-opened)

| Story | Attempts | Root cause |
|-------|----------|------------|
| 2H-002 | 2 | charts/keycloak/templates/poddisruptionbudget.yaml missing — bitnami subchart provides PDB (CI passed), but wrapper template file AC was not met |

## Quality gate improvements suggested

- Add explicit check to quality gates: for wrapper charts of bitnami/upstream charts that provide
  PDB by default, verify BOTH the wrapper template file exists AND the subchart PDB is disabled.
  Document this in the HA gate section of CLAUDE.md.

## Velocity note

Sprint points: 7 / 7 planned
Review pass rate: 75% (3 stories accepted on first review / 4 total)
Stories accepted: 4/4
