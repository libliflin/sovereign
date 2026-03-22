# Crossplane XRDs (CompositeResourceDefinitions)

This directory contains Crossplane `CompositeResourceDefinition` (XRD) resources.

XRDs define the schema for custom platform abstractions. For example, a `SovereignDatabase` XRD
would let platform users claim a managed database without knowing whether it's PostgreSQL on
Ceph, RDS, or CloudSQL.

## Pattern

1. Define the XRD schema in `<resource>-xrd.yaml`
2. Create the Composition in `../compositions/<resource>-composition.yaml`
3. Platform users create XR claims (e.g., `SovereignDatabaseClaim`)
4. Crossplane creates the backing infrastructure via the Composition

## Naming Conventions

- XRD kind: `Sovereign<Resource>` (e.g., `SovereignDatabase`, `SovereignObjectStore`)
- XRD group: `platform.sovereign.dev`
- Claim kind: `<Resource>Claim` (e.g., `DatabaseClaim`)
