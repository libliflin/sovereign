# cycle 8: check openbao initialization status
kubectl exec -n openbao openbao-0 -- bao status -tls-skip-verify

# cycle 8: initialize openbao
kubectl exec -n openbao openbao-0 -- bao operator init -key-shares=5 -key-threshold=3 -tls-skip-verify

# cycle 8: unseal openbao-0 (keys 1, 2, 3)
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 8: join openbao-1 to raft (requires leader CA cert for DNS SAN verification)
kubectl exec -n openbao openbao-1 -- bao operator raft join -tls-skip-verify -leader-ca-cert=@/openbao/tls/ca.crt "https://openbao-0.openbao-internal.openbao.svc.cluster.local:8200"

# cycle 8: unseal openbao-1 (keys 1, 2, 3)
kubectl exec -n openbao openbao-1 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-1 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-1 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 8: join openbao-2 to raft
kubectl exec -n openbao openbao-2 -- bao operator raft join -tls-skip-verify -leader-ca-cert=@/openbao/tls/ca.crt "https://openbao-0.openbao-internal.openbao.svc.cluster.local:8200"

# cycle 8: unseal openbao-2 (keys 1, 2, 3)
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 8: verify raft cluster (all 3 voters)
kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=<ROOT_TOKEN> bao operator raft list-peers -tls-skip-verify'
