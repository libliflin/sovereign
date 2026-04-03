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

# cycle 15: add jetstack helm repo (cert-manager)
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack

# cycle 15: install cert-manager (cluster recreated, Layer 1 restart)
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true --timeout 120s --wait

# cycle 14: check openbao pod status (sealed after node restart, openbao-1 missing)
kubectl get pods -n openbao

# cycle 14: unseal openbao-0 (StatefulSet OrderedReady — must unseal -0 first for -1 to be created)
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 14: unseal openbao-1 (created once openbao-0 became Ready)
kubectl exec -n openbao openbao-1 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-1 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-1 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 14: unseal openbao-2
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 14: fix harbor-database readiness probe (exec/1s → tcpSocket; QEMU: psql takes >60s to spawn)
# 1. updated values.yaml: harbor.database.internal.readinessProbe.timeoutSeconds=10
helm upgrade harbor platform/charts/harbor/ -n harbor --timeout 90s --wait  # FAILED (context canceled)
# 2. values.yaml update applied to StatefulSet spec but pod needed recreation
kubectl delete pod harbor-database-0 -n harbor --force --grace-period=0
# 3. timeoutSeconds=10 still too slow (psql >60s on QEMU) → patched to tcpSocket
kubectl patch statefulset harbor-database -n harbor --type=json -p='[...]'
kubectl delete pod harbor-database-0 -n harbor --force --grace-period=0
# Result: harbor-database-0 1/1 Ready; harbor-core connecting to DB (running migrations)
# cycle 15: install sealed-secrets controller from bitnami-labs helm chart
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets -n kube-system --set fullnameOverride=sealed-secrets-controller --timeout 90s --wait

# cycle 16: bootstrap cert-manager CA (selfsigned-issuer → sovereign-ca cert → sovereign-ca-issuer)
kubectl apply -f - # (selfsigned ClusterIssuer + sovereign-ca Certificate + sovereign-ca-issuer ClusterIssuer)
# cycle 16: install openbao (Layer 1, HA Raft, local-path storage override)
helm upgrade --install openbao platform/charts/openbao/ -n openbao --create-namespace --set global.storageClass=local-path --timeout 90s --wait

# cycle 17: check openbao initialization status
kubectl exec -n openbao openbao-0 -- bao status -address=https://openbao.openbao.svc:8200 -tls-skip-verify

# cycle 17: initialize openbao (5 shares, threshold 3)
kubectl exec -n openbao openbao-0 -- bao operator init -key-shares=5 -key-threshold=3 -tls-skip-verify
# keys saved to lathe/state/openbao-keys.json

# cycle 17: unseal openbao-0
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-0 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 17: join openbao-1 to raft and unseal
kubectl exec -n openbao openbao-1 -- bao operator raft join -tls-skip-verify -leader-ca-cert=@/openbao/tls/ca.crt "https://openbao-0.openbao-internal.openbao.svc.cluster.local:8200"
kubectl exec -n openbao openbao-1 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-1 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-1 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 17: join openbao-2 to raft and unseal
kubectl exec -n openbao openbao-2 -- bao operator raft join -tls-skip-verify -leader-ca-cert=@/openbao/tls/ca.crt "https://openbao-0.openbao-internal.openbao.svc.cluster.local:8200"
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY1>
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY2>
kubectl exec -n openbao openbao-2 -- bao operator unseal -tls-skip-verify <KEY3>

# cycle 17: verify raft cluster (all 3 voters)
kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=<ROOT_TOKEN> bao operator raft list-peers -tls-skip-verify'
# → openbao-0 leader voter:true, openbao-1 follower voter:true, openbao-2 follower voter:true

# cycle 18: check harbor PVC storageClass gap (all were empty string)
# Fixed in platform/charts/harbor/values.yaml

# cycle 18: deploy harbor
export KUBECONFIG=$(limactl list sovereign-0 --format 'unix://{{.Dir}}/copied-from-guest/kubeconfig.yaml')
helm upgrade --install harbor platform/charts/harbor/ -n harbor --create-namespace --timeout 180s

# cycle 18: confirm exec format error — amd64-only images on arm64 nodes
kubectl logs -n harbor harbor-redis-0 --previous --tail=5
# → exec /usr/bin/redis-server: exec format error

# cycle 18: verify amd64 manifest type
limactl shell sovereign-0 sudo k3s ctr content get sha256:a7fad8c1072a21345b8757f34ac75f0d9aacb06f6daa41688c7a267f44fea24a
# → "mediaType": "application/vnd.docker.distribution.manifest.v2+json" (single-arch amd64)

# cycle 18: install qemu-user-static on all nodes (binfmt_misc emulation)
limactl shell sovereign-0 sudo apt-get update -qq && limactl shell sovereign-0 sudo apt-get install -y qemu-user-static
limactl shell sovereign-1 sudo apt-get update -qq && limactl shell sovereign-1 sudo apt-get install -y qemu-user-static
limactl shell sovereign-2 sudo apt-get update -qq && limactl shell sovereign-2 sudo apt-get install -y qemu-user-static
# → qemu-x86_64 registered with POF flags

# cycle 18: force harbor-registry restart after qemu install
helm upgrade harbor platform/charts/harbor/ -n harbor --set-string "harbor.registry.podAnnotations.forceRestart=$(date +%s)" --timeout 90s
# → nginx/portal/redis came up; core/registryctl/db hit QEMU SIGSEGV

# cycle 18: confirm QEMU instability — all Harbor Go/postgres binaries hit SIGSEGV
kubectl logs -n harbor harbor-core-77849f6c68-s67zt --tail=5
# → QEMU internal SIGSEGV {code=MAPERR, addr=0x20}

# cycle 18: clean up broken harbor deployment
helm uninstall harbor -n harbor
kubectl delete pvc -n harbor --all
kubectl delete namespace harbor

# cycle 19: create Zot OCI registry chart (Layer 2 replacement for Harbor — multi-arch)
# platform/charts/zot/ — Chart.yaml, values.yaml, templates/{_helpers.tpl,configmap.yaml,deployment.yaml,service.yaml,pvc.yaml,pdb.yaml}

# cycle 19: lint and autarky gate
helm lint platform/charts/zot/
grep -rn "docker\.io\|quay\.io\|ghcr\.io\|gcr\.io\|registry\.k8s\.io" platform/charts/*/templates/ && echo "FAIL" || echo "PASS"

# cycle 19: deploy Zot
helm upgrade --install zot platform/charts/zot/ -n zot --create-namespace --timeout 120s

# cycle 19: verify Zot OCI v2 endpoint
kubectl run zot-check2 --rm -i --restart=Never --image=busybox -- wget -S -qO- http://zot.zot.svc.cluster.local:5000/v2/

# cycle 20: enable Zot pull-through proxy (sync extension, onDemand for 5 upstream registries)
helm upgrade --install zot platform/charts/zot/ -n zot --create-namespace --timeout 120s --wait
# cycle 20: verify Zot OCI v2 API after sync extension enabled
kubectl run zot-verify2 --rm -i --restart=Never --image=busybox -- wget -S -qO- http://zot.zot.svc.cluster.local:5000/v2/
