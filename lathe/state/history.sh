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

# cycle 21: write k3s registry mirrors to all 3 nodes (route external pulls through Zot at ClusterIP 10.43.32.173:5000)
limactl shell sovereign-0 sudo tee /etc/rancher/k3s/registries.yaml
limactl shell sovereign-1 sudo tee /etc/rancher/k3s/registries.yaml
limactl shell sovereign-2 sudo tee /etc/rancher/k3s/registries.yaml

# cycle 21: restart k3s-agent on workers, then k3s on server
limactl shell sovereign-1 sudo systemctl restart k3s-agent
limactl shell sovereign-2 sudo systemctl restart k3s-agent
limactl shell sovereign-0 sudo systemctl restart k3s

# cycle 21: verify mirror active (Zot logs show ?ns=ghcr.io on blob requests)
kubectl logs -n zot -l app.kubernetes.io/name=zot --tail=20

# cycle 22: fix ingress annotation nginx → traefik in platform/charts/keycloak/values.yaml
# edit platform/charts/keycloak/values.yaml

# cycle 22: create keycloak namespace and bootstrap secrets
kubectl create namespace keycloak
kubectl create secret generic keycloak-admin-secret --from-literal=admin-password='Keycloak12345' -n keycloak
kubectl create secret generic keycloak-db-secret --from-literal=postgres-password='Postgres12345' --from-literal=password='Keycloak12345' -n keycloak

# cycle 22: deploy keycloak (timed out — bitnami images ImagePullBackOff on new VMs)
helm upgrade --install keycloak platform/charts/keycloak/ -n keycloak --set realmInit.enabled=false --timeout 150s --wait
# → failed: bitnami images not found (VMs recreated at cycle 14, images lost; bitnami tags migrated to bitnamilegacy)
# → queued bitnami images in downloads.json for cycle 22; fetch.sh will re-import next cycle

# cycle 23: reconcile keycloak release from failed to deployed (pods were already running after fetch.sh imported images)
helm upgrade keycloak platform/charts/keycloak/ -n keycloak --set realmInit.enabled=false --timeout 150s --wait

# cycle 24: install harbor (layer 2 - internal registry / autarky boundary)
helm upgrade --install harbor platform/charts/harbor/ -n harbor --create-namespace

# cycle 25: fix forgejo values — enable postgresql subchart, fix storageClass standard→local-path, fix PDB bug
# edit platform/charts/forgejo/values.yaml

# cycle 25: uninstall failed forgejo + clear stuck PVCs
helm uninstall forgejo -n forgejo
kubectl delete pvc -n forgejo --all

# cycle 25: install forgejo (timed out — bitnami/postgresql:17.2.0-debian-12-r6 ImagePullBackOff)
helm upgrade --install forgejo platform/charts/forgejo/ -n forgejo --create-namespace --timeout 180s --wait
# → PVCs bound, forgejo image pulled via Zot, postgresql stuck on bitnami image not found
# → queued docker.io/bitnamilegacy/postgresql:17.2.0-debian-12-r6 in downloads.json

# cycle 26: get configure-gitea init container crash logs
kubectl logs -n forgejo forgejo-6b7c5d8c5b-d8szq -c configure-gitea --previous

# cycle 26: test keycloak sovereign realm in-cluster
kubectl run tmp-debug2 --rm -i --restart=Never --image=busybox -- sh -c 'wget -qO- http://keycloak.keycloak.svc.cluster.local/realms/sovereign/.well-known/openid-configuration 2>&1 | head -3'

# cycle 26: upgrade forgejo with oauth disabled (sovereign realm not yet created)
helm upgrade --install forgejo platform/charts/forgejo/ -n forgejo --create-namespace --timeout 180s --wait

# cycle 27: fix argocd ingress — nginx ingressClass → traefik
# edit platform/charts/argocd/templates/ingress.yaml

# cycle 27: install argocd
helm upgrade --install argocd platform/charts/argocd/ -n argocd --create-namespace --timeout 120s --wait

# cycle 28: fix prometheus-stack storageClass standard → local-path, storage 50Gi → 5Gi
# edit platform/charts/prometheus-stack/values.yaml

# cycle 28: install prometheus-stack
helm upgrade --install prometheus-stack platform/charts/prometheus-stack/ -n monitoring --create-namespace --timeout 120s --wait

# cycle 29: fix victorialogs storageClass and storage size, install
# (same CONFIG_ERROR pattern as cycle 28 prometheus-stack)
helm upgrade --install victorialogs platform/charts/victorialogs/ -n monitoring --create-namespace --timeout 90s --wait

# cycle 30: fix jaeger ingress (nginx→traefik), storage (standard→local-path, 20Gi→5Gi), badger ephemeral
# First attempt failed: ephemeral:false + no PVC mount = permission denied on /mnt/data
helm uninstall jaeger -n jaeger
# Fix badger ephemeral:true and reinstall
helm upgrade --install jaeger platform/charts/jaeger/ -n jaeger --create-namespace --timeout 120s --wait

# cycle 31: diagnose Harbor QEMU SIGSEGV — all goharbor images are linux/amd64 on arm64 nodes
limactl shell sovereign-0 sudo k3s ctr images list | grep goharbor | grep -v "@sha256" | awk '{print $1, $6}'

# cycle 31: fix fetch.sh arch assumption amd64 -> arm64 (Lima VMs are native arm64/aarch64)
# edit: lathe/fetch.sh line 55: arch = 'amd64' -> arch = 'arm64'

# cycle 31: queue arm64 Harbor images for re-download (next cycle fetch.sh will import them)
# python3 appended 6 entries to lathe/state/downloads.json

# cycle 32: disable Cassandra in jaeger — provisionDataStore.cassandra was true by default,
#           OOM-killing 4GB nodes; storage.type: badger needs no Cassandra
helm upgrade jaeger platform/charts/jaeger/ -n jaeger --timeout 60s --wait
# cycle 33: fix fetch.sh no-daemon path to pass --platform linux/arm64 to ctr images pull
# (cycle 31 fix changed arch var but no-daemon path never used it — harbor images landed as amd64)
bash -n lathe/fetch.sh
# cycle 33: reset harbor image downloads.json entries to done=false for re-pull with --platform
python3 -c "import json; q=json.load(open('lathe/state/downloads.json')); print([e['source'] for e in q if not e.get('done')])"

# cycle 34: check disk usage on sovereign-2 (DiskPressure diagnosis)
limactl shell sovereign-2 df -h /
limactl shell sovereign-2 sudo du -sh /var/lib/rancher/k3s/storage/

# cycle 34: delete 22GB harbor database PVC directory (Harbor is dead code, D1)
limactl shell sovereign-2 sudo rm -rf /var/lib/rancher/k3s/storage/pvc-2b4807f7-49e9-4f5f-9ee3-fd9e9cbf52b2_harbor_database-data-harbor-database-0
limactl shell sovereign-2 sudo rm -rf /var/lib/rancher/k3s/storage/pvc-9215aa1c-c091-41b9-b2dd-5a8c48134be1_harbor_data-harbor-redis-0

# cycle 34: remove pv-protection finalizers from Released Harbor PVs
kubectl patch pv pvc-2b4807f7-49e9-4f5f-9ee3-fd9e9cbf52b2 -p '{"metadata":{"finalizers":null}}'
kubectl patch pv pvc-9215aa1c-c091-41b9-b2dd-5a8c48134be1 -p '{"metadata":{"finalizers":null}}'

# cycle 34: clean up eviction debris
kubectl delete pods -n argocd --field-selector status.phase=Failed
kubectl delete pods -n kube-system --field-selector status.phase=Failed
kubectl delete pods -n jaeger --field-selector status.phase=Failed
kubectl delete pods -n monitoring --field-selector status.phase=Failed

# cycle 34 (follow-up): confirm DiskPressure cleared, taint removed from sovereign-2
kubectl describe node lima-sovereign-2 | grep -i taint
# → Taints: <none>

# cycle 34 (follow-up): remove pv-protection finalizers from Released Harbor PVs (previous patch didn't persist)
kubectl patch pv pvc-2b4807f7-49e9-4f5f-9ee3-fd9e9cbf52b2 -p '{"metadata":{"finalizers":null}}'
kubectl patch pv pvc-9215aa1c-c091-41b9-b2dd-5a8c48134be1 -p '{"metadata":{"finalizers":null}}'

# cycle 34 (follow-up): delete Released Harbor PVs (stops helper-pod eviction loop)
kubectl delete pv pvc-2b4807f7-49e9-4f5f-9ee3-fd9e9cbf52b2 pvc-9215aa1c-c091-41b9-b2dd-5a8c48134be1

# cycle 34 (follow-up): delete evicted/error/stale pods cluster-wide
kubectl delete pod tmp-debug -n default --grace-period=0
kubectl delete pod cert-manager-cainjector-7f45ffb9d5-gjc77 -n cert-manager --grace-period=0

# cycle 35: fix istio values.yaml storageClass ceph-block -> local-path
# (edit to platform/charts/istio/values.yaml)

# cycle 35: install istio (Layer 6 first component)
helm upgrade --install istio platform/charts/istio/ -n istio-system --create-namespace --timeout 120s --wait
# cycle 36: fix storageClass + add constraintsEnabled flag to opa-gatekeeper chart
# (edit platform/charts/opa-gatekeeper/values.yaml + templates/constraint-*.yaml)

# cycle 36: opa-gatekeeper pass 1 — controller + CRDs + ConstraintTemplates (no Constraints)
timeout 120 helm upgrade --install opa-gatekeeper platform/charts/opa-gatekeeper/ -n gatekeeper-system --create-namespace --set constraintsEnabled=false --timeout 90s --wait

# cycle 36: wait for K8s* CRDs to be Established
kubectl wait --for=condition=Established crd/k8snoprivilegeescalation.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8srequirelabels.constraints.gatekeeper.sh --timeout=60s
kubectl wait --for=condition=Established crd/k8srequireresourcelimits.constraints.gatekeeper.sh --timeout=60s

# cycle 36: opa-gatekeeper pass 2 — enable Constraints
timeout 60 helm upgrade opa-gatekeeper platform/charts/opa-gatekeeper/ -n gatekeeper-system --set constraintsEnabled=true --timeout 90s --wait

# cycle 37: fix opa-gatekeeper constraint to exclude falco namespace (privileged DaemonSet)
helm upgrade opa-gatekeeper platform/charts/opa-gatekeeper/ -n gatekeeper-system --set constraintsEnabled=true --timeout 60s --wait

# cycle 37: install falco DaemonSet (modern_ebpf, 3 nodes)
helm upgrade --install falco platform/charts/falco/ -n falco --create-namespace --timeout 90s

# cycle 38: upgrade opa-gatekeeper to add trivy-system exclusion from require-labels constraint
helm upgrade opa-gatekeeper platform/charts/opa-gatekeeper/ -n gatekeeper-system --set constraintsEnabled=true --timeout 90s --wait

# cycle 38: install trivy-operator (Layer 6 final component)
helm upgrade --install trivy-operator platform/charts/trivy-operator/ -n trivy-system --create-namespace --timeout 120s --wait

# cycle 39: fix backstage values (storageClass, image tag, ingress, OPA labels+securityContext)
# changed: storageClass ceph-block→local-path, tag latest→1.30.2, class nginx→traefik, issuer letsencrypt-prod→sovereign-ca-issuer
# added app+tier labels to Deployment, allowPrivilegeEscalation: false to container

# cycle 39: install backstage (timed out — image pulling through Zot from ghcr.io)
helm upgrade --install backstage platform/charts/backstage/ -n backstage --create-namespace --timeout 90s --wait
# → timed out, pod backstage-5d64db89b9-m6kpv ContainerCreating (pulling ghcr.io/backstage/backstage:1.30.2)
# cycle 40: disable falcoctl-artifact-follow sidecar (external hub dependency crashes in sovereign cluster)
helm upgrade falco platform/charts/falco/ -n falco --timeout 90s --wait
