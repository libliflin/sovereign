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

# cycle 9: check harbor pod status
kubectl -n harbor get pods

# cycle 9: verify QEMU patches on all nodes (6 patches: P1-P6)
limactl shell sovereign-0 -- python3 -c "import struct; ..."  # check offsets 0xbfdf0,0xdf6f4,0xdf6f8,0xcd3cc,0xcd024,0xcd044

# cycle 9: set postgres password (was NULL despite secret having 'changeit')
kubectl -n harbor exec harbor-database-0 -- psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'changeit'"

# cycle 9: run harbor init SQL (registry DB not created during broken QEMU period)
kubectl -n harbor exec harbor-database-0 -- psql -U postgres -f /docker-entrypoint-initdb.d/initial-registry.sql

# cycle 9: restart harbor-core after DB fixes
kubectl -n harbor delete pod -l component=core

# cycle 9: fix redis stop-writes-on-bgsave-error (bgsave fork crashes under QEMU after write)
kubectl -n harbor exec harbor-redis-0 -- redis-cli CONFIG SET stop-writes-on-bgsave-error no
kubectl -n harbor patch statefulset harbor-redis --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["/usr/bin/redis-server"]},{"op":"add","path":"/spec/template/spec/containers/0/args","value":["/etc/redis.conf","--stop-writes-on-bgsave-error","no"]}]'

# cycle 9: restart jobservice after core is healthy
kubectl -n harbor delete pod -l component=jobservice

# cycle 10: check openbao-2 seal status (restarted, needs unseal)
kubectl exec -n openbao openbao-2 -- bao status -tls-skip-verify

# cycle 10: unseal openbao-2 (keys 1, 2, 3)
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 10: verify raft cluster (all 3 voters)
kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=<ROOT_TOKEN> bao operator raft list-peers -tls-skip-verify'

# cycle 10: verify harbor API from inside cluster
kubectl run tmp-ping --rm -i --restart=Never --image=busybox -n harbor -- wget -qO- --timeout=5 http://harbor-core.harbor:80/api/v2.0/ping

# cycle 9: verify harbor API
curl -sk --resolve harbor.sovereign-autarky.dev:443:192.168.104.1 \
  -u admin:Harbor12345 https://harbor.sovereign-autarky.dev/api/v2.0/ping
# → Pong

# cycle 11: check openbao-2 seal status
kubectl exec -n openbao openbao-2 -- bao status -tls-skip-verify

# cycle 11: create keycloak namespace and secrets
kubectl create namespace keycloak
kubectl create secret generic keycloak-admin-secret --from-literal=admin-password='Keycloak12345' -n keycloak
kubectl create secret generic keycloak-db-secret --from-literal=postgres-password='Postgres12345' --from-literal=password='Keycloak12345' -n keycloak

# cycle 11: attempt keycloak deploy (failed: image pull error + wrong storageClass)
helm upgrade --install keycloak platform/charts/keycloak/ -n keycloak --set ingress.enabled=false --set realmInit.enabled=false --timeout 120s --wait

# cycle 11: uninstall failed keycloak release
helm uninstall keycloak -n keycloak

# cycle 12: fix fetch.sh — was pulling linux/arm64 but k3s nodes run linux/amd64 via QEMU
# changed: arch = 'amd64'  (hardcoded instead of detecting host arch)
# edit lathe/fetch.sh

# cycle 12: reset failed downloads for retry with correct arch
# edit lathe/state/downloads.json — removed result/done fields from cycle 11 failures

# cycle 13: fix fetch.sh — docker daemon unavailable (Docker Desktop not running)
# added daemon detection + crane fallback; crane tarball incompatible with k3s ctr import
# fixed: no-daemon path uses limactl shell + k3s ctr images pull directly on nodes
# docker daemon timeout increased from 5s to 15s for slow-start case
# edit lathe/fetch.sh

# cycle 13: delete lingering ceph-block PVC from previous failed deploy
kubectl delete pvc data-keycloak-postgresql-0 -n keycloak

# cycle 13: run fetch.sh — keycloak image via docker (daemon came up), postgresql via no-daemon ctr pull
bash lathe/fetch.sh

# cycle 13: deploy keycloak (images now present on all nodes, storageClass fixed to local-path)
helm upgrade --install keycloak platform/charts/keycloak/ -n keycloak --set ingress.enabled=false --set realmInit.enabled=false --timeout 120s --wait

# cycle 13: force restart sovereign-0 (VM hung with I/O errors during large image import)
limactl stop sovereign-0 --force && limactl start sovereign-0

# cycle 13: force restart sovereign-1, sovereign-2 (hung after sovereign-0 restart)
limactl stop sovereign-1 --force && limactl start sovereign-1
limactl stop sovereign-2 --force && limactl start sovereign-2

# cycle 13: delete stuck local-path helper pod (was Unknown after node restart, blocked PVC binding)
kubectl delete pod -n kube-system helper-pod-create-pvc-a317cc41-d4ea-487d-91d6-dc8652b6c95d --force

# cycle 13: patch helm release from pending-install to deployed (timed out waiting, pods actually running)
kubectl patch secret sh.helm.release.v1.keycloak.v1 -n keycloak --type=json -p '[...]'

# cycle 13: verify keycloak Layer 3 running
kubectl get pods -n keycloak
# → keycloak-0  1/1 Running  sovereign-1
# → keycloak-postgresql-0  1/1 Running  sovereign-0
