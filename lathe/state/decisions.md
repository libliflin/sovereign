# Permanent Decisions

These decisions have been made and must not be revisited. Read this before every cycle.

## D1: Zot replaces Harbor as Layer 2 registry (Cycle 18-19)

**Decision:** Use Zot (CNCF Sandbox, Apache 2.0) instead of Harbor for the internal
container registry.

**Reason:** Harbor only publishes amd64 images. Our Lima VMs run arm64 (Apple Silicon
with Apple Virtualization.framework). Harbor's Go binaries and PostgreSQL SIGSEGV under
QEMU user-mode emulation. This is not fixable — Harbor upstream does not ship arm64.

**Implication:** Never install, deploy, or pull Harbor images. The chart at
`platform/charts/harbor/` is dead code on arm64. Layer 2 is `platform/charts/zot/`.
`global.imageRegistry` should point to the Zot service.
