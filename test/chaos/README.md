# Chaos PDB Validation

This directory contains Chaos Mesh experiment manifests for validating that
PodDisruptionBudgets (PDB) prevent simultaneous pod eviction on the Sovereign Platform.

## What this tests

`pdb-validation.yaml` is a Chaos Mesh `PodChaos` experiment that simultaneously kills
all pods in the `grafana` namespace. With a `PodDisruptionBudget` of `minAvailable: 1`
in place, Chaos Mesh (or the underlying eviction API) should refuse to evict the last
pod, keeping at least one Grafana instance available.

This validates the E15 HA invariant: the PDB enforcer protects services from total
outage during maintenance or chaos events.

## Prerequisites

- A running kind cluster with Chaos Mesh installed (see TEST-004 story)
- Grafana deployed with a PDB specifying `minAvailable: 1`
- `kubectl` configured to target the kind cluster

## Apply the experiment

```bash
kubectl apply -f test/chaos/pdb-validation.yaml
```

## Observe PDB enforcement

Watch Grafana pods during the experiment:

```bash
kubectl get pods -n grafana -w
```

Expected behavior:
- Chaos Mesh attempts to kill all Grafana pods simultaneously
- The PodDisruptionBudget prevents eviction of the last remaining pod
- At least one Grafana pod remains `Running` throughout the experiment
- After the 30-second `duration`, pods recover to the desired replica count

If the PDB is absent or misconfigured, all pods will be killed simultaneously
and Grafana will be temporarily unavailable — a HA violation.

## Verify PDB is present

```bash
kubectl get pdb -n grafana
```

The output should show a PDB with `MIN AVAILABLE: 1` and `ALLOWED DISRUPTIONS: <n-1>`.

## Clean up

```bash
kubectl delete -f test/chaos/pdb-validation.yaml
```

## Notes

- This experiment is a static test artifact — it does not run in CI
- Apply it manually against a kind cluster with Chaos Mesh running
- Extend to other namespaces (loki, tempo, keycloak) by duplicating the manifest
  with the appropriate `namespaces` and `labelSelectors`
