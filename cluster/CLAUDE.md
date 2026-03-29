# Cluster Bootstrap

## HA Requirements

bootstrap.sh MUST refuse to proceed with fewer than 3 nodes or an even node count.
HA is not optional. It is baked in from the first commit.

```
Node layer:      3+ nodes (odd). etcd quorum + Ceph quorum require this.
API server:      kube-vip floating VIP across all control plane nodes.
CNI:             Cilium DaemonSet — inherently HA.
Storage:         Rook/Ceph replication factor 3.
```

## Provider Scripts

Every provider script (`cluster/*/bootstrap.sh`) must:
1. Accept `config.yaml` (domain, SSH key, `nodes.count`, `nodes.serverType`)
2. Validate `nodes.count` is odd and >= 3
3. Provision all N nodes
4. Install kube-vip for floating API server VIP
5. Install K3s with `--cluster-init` on node 1, join via VIP on nodes 2+
6. Verify ALL nodes are `Ready` before outputting kubeconfig
7. Output kubeconfig pointing at the kube-vip VIP (not a single node IP)

## Testing

Bootstrap scripts are tested statically only: `shellcheck -S error` + `bash -n`.
Never run bootstrap.sh in full execution mode during a story — those are manual
steps the human runs when provisioning real infrastructure.

kind is the local development cluster. Check `kind get clusters` before creating one.

## Provider Documentation

Each provider's docs must include:
- Estimated cost for 3-node HA cluster (minimum)
- Prerequisites (CLI tools, accounts)
- Step-by-step with copy-pasteable commands
- How to add/replace nodes without downtime
