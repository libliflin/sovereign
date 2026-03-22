# Crossplane Compositions

This directory contains Crossplane `Composition` resources that implement the XRDs defined in `../xrds/`.

A Composition maps an XRD claim to concrete managed resources. For example, the `SovereignDatabase`
XRD might have a Composition that creates a PostgreSQL deployment on Ceph storage.

## Pattern

Each Composition:
1. References an XRD (via `compositeTypeRef`)
2. Defines `resources[]` — the concrete K8s/Helm resources to create
3. Uses patches to propagate XR fields to managed resources

## Example

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: sovereign-database-ceph
spec:
  compositeTypeRef:
    apiVersion: platform.sovereign.dev/v1alpha1
    kind: SovereignDatabase
  resources:
    - name: postgresql
      base:
        apiVersion: helm.crossplane.io/v1beta1
        kind: Release
        spec:
          forProvider:
            chart:
              name: postgresql
              repository: https://charts.bitnami.com/bitnami
```
