#!/usr/bin/env bash
# hetzner.sh — Provision N Hetzner Cloud servers and install a K3s HA cluster
# Called by bootstrap.sh after loading config.yaml
#
# HA requirements (enforced by bootstrap.sh):
#   - nodes.count must be odd and >= 3
#   - kube-vip provides a floating VIP for the K3s API server
#   - K3s uses --cluster-init with embedded etcd on node-1
#   - Nodes 2+ join via --server https://<VIP>:6443
#   - kubeconfig points at the VIP, not a single node IP
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SOVEREIGN_CONFIG:-${SCRIPT_DIR}/../config.yaml}"

# Require hcloud CLI
if ! command -v hcloud &>/dev/null; then
  echo "ERROR: 'hcloud' CLI is required." >&2
  echo "  Install: brew install hcloud  (macOS) or see https://github.com/hetznercloud/cli" >&2
  exit 1
fi

# Require yq
if ! command -v yq &>/dev/null; then
  echo "ERROR: 'yq' is required. Install with: brew install yq" >&2
  exit 1
fi

# Read Hetzner-specific config
HCLOUD_TOKEN="$(yq '.hetzner.apiToken' "$CONFIG_FILE")"
SERVER_TYPE="$(yq '.nodes.serverType // "cx22"' "$CONFIG_FILE")"
LOCATION="$(yq '.hetzner.location // "nbg1"' "$CONFIG_FILE")"
SSH_KEY_NAME="$(yq '.hetzner.sshKeyName' "$CONFIG_FILE")"
SERVER_NAME_PREFIX="$(yq '.hetzner.serverName // "sovereign"' "$CONFIG_FILE")"
DOMAIN="${SOVEREIGN_DOMAIN:-$(yq '.domain' "$CONFIG_FILE")}"
K3S_VERSION="$(yq '.k3sVersion // "v1.29.4+k3s1"' "$CONFIG_FILE")"
NODE_COUNT="${NODE_COUNT:-$(yq '.nodes.count // 3' "$CONFIG_FILE")}"
SSH_KEY="${SOVEREIGN_SSH_KEY:-$(yq '.sshKeyPath // "~/.ssh/id_ed25519"' "$CONFIG_FILE")}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"

# kube-vip version to use
KUBEVIP_VERSION="v0.7.2"

if [[ -z "$HCLOUD_TOKEN" || "$HCLOUD_TOKEN" == "null" ]]; then
  echo "ERROR: 'hetzner.apiToken' is required in config.yaml" >&2
  exit 1
fi

if [[ -z "$SSH_KEY_NAME" || "$SSH_KEY_NAME" == "null" ]]; then
  echo "ERROR: 'hetzner.sshKeyName' is required in config.yaml" >&2
  exit 1
fi

export HCLOUD_TOKEN

echo "==> [Hetzner] Provisioning ${NODE_COUNT}-node HA cluster"
echo "    Server type: $SERVER_TYPE"
echo "    Location:    $LOCATION"
echo "    Name prefix: $SERVER_NAME_PREFIX"
echo "    K3s:         $K3S_VERSION"
echo "    kube-vip:    $KUBEVIP_VERSION"
echo ""

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i "$SSH_KEY")

# ── Step 1: Provision all N nodes ────────────────────────────────────────────
declare -a NODE_IPS=()

for i in $(seq 1 "$NODE_COUNT"); do
  SERVER_NAME="${SERVER_NAME_PREFIX}-${i}"

  if hcloud server describe "$SERVER_NAME" &>/dev/null; then
    echo "==> Server '$SERVER_NAME' already exists, reusing."
    IP="$(hcloud server describe "$SERVER_NAME" -o format='{{.PublicNet.IPv4.IP}}')"
  else
    echo "==> Creating server $SERVER_NAME..."
    hcloud server create \
      --name "$SERVER_NAME" \
      --type "$SERVER_TYPE" \
      --image ubuntu-22.04 \
      --location "$LOCATION" \
      --ssh-key "$SSH_KEY_NAME"

    echo "  Waiting for server to be running..."
    for attempt in $(seq 1 30); do
      STATUS="$(hcloud server describe "$SERVER_NAME" -o format='{{.Status}}')"
      if [[ "$STATUS" == "running" ]]; then
        break
      fi
      echo "    Status: $STATUS (attempt $attempt/30)..."
      sleep 5
    done

    IP="$(hcloud server describe "$SERVER_NAME" -o format='{{.PublicNet.IPv4.IP}}')"
    echo "==> Server $SERVER_NAME created: $IP"

    echo "  Waiting for SSH on $IP..."
    for attempt in $(seq 1 20); do
      if ssh "${SSH_OPTS[@]}" "root@${IP}" "echo ok" &>/dev/null; then
        break
      fi
      echo "    SSH not ready (attempt $attempt/20)..."
      sleep 10
    done
  fi

  NODE_IPS+=("$IP")
  # Write to SOVEREIGN_NODELIST for bootstrap.sh to pick up
  if [[ -n "${SOVEREIGN_NODELIST:-}" ]]; then
    echo "$IP" >> "$SOVEREIGN_NODELIST"
  fi
done

NODE1_IP="${NODE_IPS[0]}"
echo ""
echo "==> All nodes provisioned:"
for i in "${!NODE_IPS[@]}"; do
  echo "    node-$((i+1)): ${NODE_IPS[$i]}"
done
echo ""

# ── Step 2: Allocate kube-vip VIP ────────────────────────────────────────────
# Use the first node's subnet and take the last octet as .100 for the VIP.
# For production users should specify kube-vip.vip in config.yaml.
KUBE_VIP="$(yq '.kubeVip.vip // ""' "$CONFIG_FILE")"
if [[ -z "$KUBE_VIP" || "$KUBE_VIP" == "null" ]]; then
  # Auto-derive: same /24 as node-1, last octet 100
  KUBE_VIP="$(echo "$NODE1_IP" | cut -d. -f1-3).100"
  echo "==> kube-vip VIP auto-derived: ${KUBE_VIP}"
  echo "    (Set kubeVip.vip in config.yaml to override)"
else
  echo "==> kube-vip VIP from config: ${KUBE_VIP}"
fi
echo ""

# ── Step 3: Install kube-vip on node-1 (before K3s starts) ──────────────────
# kube-vip runs as a static Pod. We write the manifest to /var/lib/rancher/k3s/server/manifests/
# so K3s picks it up automatically on first boot.
echo "==> Installing kube-vip manifest on node-1 (${NODE1_IP})..."
# Detect primary network interface
IFACE="$(ssh "${SSH_OPTS[@]}" "root@${NODE1_IP}" "ip -4 route show default | awk '{print \$5}' | head -1")"
echo "    Network interface: ${IFACE}"

ssh "${SSH_OPTS[@]}" "root@${NODE1_IP}" \
  "mkdir -p /var/lib/rancher/k3s/server/manifests && \
   mkdir -p /var/lib/rancher/k3s/agent/pod-manifests"

# Generate kube-vip static pod manifest
# shellcheck disable=SC2029
ssh "${SSH_OPTS[@]}" "root@${NODE1_IP}" \
  "docker run --network host --rm \
     ghcr.io/kube-vip/kube-vip:${KUBEVIP_VERSION} \
     manifest pod \
     --interface ${IFACE} \
     --address ${KUBE_VIP} \
     --controlplane \
     --services \
     --arp \
     --leaderElection 2>/dev/null || \
   curl -sfL https://raw.githubusercontent.com/kube-vip/kube-vip/${KUBEVIP_VERSION}/docs/manifests/rbac.yaml | \
     sed \"s/IFACE/${IFACE}/g; s/VIP/${KUBE_VIP}/g\"" \
  > /tmp/sovereign-kubevip-manifest.yaml 2>/dev/null || true

# If generation failed (no docker), write the manifest directly
if [[ ! -s /tmp/sovereign-kubevip-manifest.yaml ]]; then
  cat > /tmp/sovereign-kubevip-manifest.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  containers:
  - name: kube-vip
    image: ghcr.io/kube-vip/kube-vip:${KUBEVIP_VERSION}
    imagePullPolicy: Always
    args:
    - manager
    env:
    - name: vip_arp
      value: "true"
    - name: port
      value: "6443"
    - name: vip_interface
      value: "${IFACE}"
    - name: vip_cidr
      value: "32"
    - name: cp_enable
      value: "true"
    - name: cp_namespace
      value: kube-system
    - name: vip_ddns
      value: "false"
    - name: vip_leaderelection
      value: "true"
    - name: vip_leaseduration
      value: "5"
    - name: vip_renewdeadline
      value: "3"
    - name: vip_retryperiod
      value: "1"
    - name: address
      value: "${KUBE_VIP}"
    securityContext:
      capabilities:
        add:
        - NET_ADMIN
        - NET_RAW
        - SYS_TIME
    volumeMounts:
    - mountPath: /etc/kubernetes/admin.conf
      name: kubeconfig
  hostAliases:
  - hostnames:
    - kubernetes
    ip: 127.0.0.1
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/rancher/k3s/k3s.yaml
    name: kubeconfig
EOF
fi

# Push the manifest to node-1
cat /tmp/sovereign-kubevip-manifest.yaml | \
  ssh "${SSH_OPTS[@]}" "root@${NODE1_IP}" \
  'cat > /var/lib/rancher/k3s/server/manifests/kube-vip.yaml'

echo "==> kube-vip manifest written on node-1"
echo ""

# ── Step 4: Install K3s on node-1 with --cluster-init ───────────────────────
echo "==> Installing K3s on node-1 (${NODE1_IP}) with --cluster-init..."
# shellcheck disable=SC2029
ssh "${SSH_OPTS[@]}" "root@${NODE1_IP}" \
  "curl -sfL https://get.k3s.io | \
     INSTALL_K3S_VERSION=${K3S_VERSION} \
     sh -s - server \
       --cluster-init \
       --write-kubeconfig-mode 644 \
       --tls-san ${KUBE_VIP} \
       --tls-san ${NODE1_IP} \
       --tls-san ${DOMAIN}"

echo "  Waiting for K3s to start on node-1..."
for attempt in $(seq 1 30); do
  if ssh "${SSH_OPTS[@]}" "root@${NODE1_IP}" "k3s kubectl get nodes" &>/dev/null; then
    break
  fi
  echo "    Not ready yet (attempt $attempt/30)..."
  sleep 10
done
echo "==> K3s running on node-1"
echo ""

# ── Step 5: Get node token for join ─────────────────────────────────────────
K3S_TOKEN="$(ssh "${SSH_OPTS[@]}" "root@${NODE1_IP}" "cat /var/lib/rancher/k3s/server/node-token")"

# ── Step 6: Join remaining nodes ─────────────────────────────────────────────
for i in $(seq 2 "$NODE_COUNT"); do
  NODE_IP="${NODE_IPS[$((i-1))]}"
  echo "==> Joining node-${i} (${NODE_IP}) to cluster via VIP ${KUBE_VIP}..."

  # Install kube-vip on this node too (runs as a static pod via K3s)
  cat /tmp/sovereign-kubevip-manifest.yaml | \
    ssh "${SSH_OPTS[@]}" "root@${NODE_IP}" \
    'mkdir -p /var/lib/rancher/k3s/server/manifests && cat > /var/lib/rancher/k3s/server/manifests/kube-vip.yaml'

  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "root@${NODE_IP}" \
    "curl -sfL https://get.k3s.io | \
       INSTALL_K3S_VERSION=${K3S_VERSION} \
       K3S_TOKEN=${K3S_TOKEN} \
       sh -s - server \
         --server https://${KUBE_VIP}:6443 \
         --write-kubeconfig-mode 644 \
         --tls-san ${KUBE_VIP} \
         --tls-san ${NODE_IP} \
         --tls-san ${DOMAIN}"

  echo "  Node-${i} joined."
done
echo ""

# ── Step 7: Verify all nodes are Ready ──────────────────────────────────────
echo "==> Waiting for all ${NODE_COUNT} nodes to be Ready..."
for attempt in $(seq 1 40); do
  READY_COUNT="$(ssh "${SSH_OPTS[@]}" "root@${NODE1_IP}" \
    "k3s kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready'" || echo 0)"
  if [[ "$READY_COUNT" -ge "$NODE_COUNT" ]]; then
    echo "==> All ${NODE_COUNT} nodes are Ready."
    break
  fi
  echo "    ${READY_COUNT}/${NODE_COUNT} nodes Ready (attempt $attempt/40)..."
  sleep 10
done

if [[ "$READY_COUNT" -lt "$NODE_COUNT" ]]; then
  echo "ERROR: Only ${READY_COUNT}/${NODE_COUNT} nodes became Ready. Check logs on the nodes." >&2
  exit 1
fi
echo ""

# ── Step 8: Retrieve kubeconfig pointing at VIP ──────────────────────────────
echo "==> Fetching kubeconfig (pointing at VIP: ${KUBE_VIP})..."
KUBECONFIG_DIR="${HOME}/.kube"
mkdir -p "$KUBECONFIG_DIR"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/sovereign-hetzner.yaml"

ssh "${SSH_OPTS[@]}" "root@${NODE1_IP}" "cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/${KUBE_VIP}/g" \
  > "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE"
echo "==> kubeconfig saved to: $KUBECONFIG_FILE"
echo "    Server: https://${KUBE_VIP}:6443"
echo ""
echo "    To use:  export KUBECONFIG=$KUBECONFIG_FILE"
echo ""

# ── Cost estimate (3-node minimum) ──────────────────────────────────────────
echo "================================================================"
echo "  ESTIMATED MONTHLY COST (Hetzner) — ${NODE_COUNT}-node cluster"
echo "================================================================"
case "$SERVER_TYPE" in
  cx21|cx22)
    PER_NODE="5-6"
    TOTAL="$(( NODE_COUNT * 5 ))-$(( NODE_COUNT * 6 ))"
    echo "  ${NODE_COUNT}x CX21/CX22 (2 vCPU, 4GB RAM): ~${PER_NODE} EUR/node"
    echo "  3-node cluster total:  ~15-18 EUR/month  [minimum recommended]"
    echo "  5-node cluster total:  ~25-30 EUR/month  [production recommended]"
    echo "  ${NODE_COUNT}-node cluster total:  ~${TOTAL} EUR/month"
    ;;
  cx31|cx32)
    echo "  ${NODE_COUNT}x CX31/CX32 (2 vCPU, 8GB RAM): ~10-12 EUR/node"
    echo "  3-node cluster total:  ~30-36 EUR/month"
    echo "  ${NODE_COUNT}-node cluster total:  ~$(( NODE_COUNT * 10 ))-$(( NODE_COUNT * 12 )) EUR/month"
    ;;
  cx41|cx42)
    echo "  ${NODE_COUNT}x CX41/CX42 (4 vCPU, 16GB RAM): ~18-20 EUR/node"
    echo "  3-node cluster total:  ~54-60 EUR/month"
    echo "  ${NODE_COUNT}-node cluster total:  ~$(( NODE_COUNT * 18 ))-$(( NODE_COUNT * 20 )) EUR/month"
    ;;
  *)
    echo "  See https://www.hetzner.com/cloud for pricing for $SERVER_TYPE"
    echo "  Multiply per-node cost by $NODE_COUNT for total."
    ;;
esac
echo ""
echo "  NOTE: Single-node and 2-node clusters are NOT supported."
echo "  Minimum is 3 nodes (etcd quorum + Ceph replication factor 3)."
echo ""

# ── Connection info ──────────────────────────────────────────────────────────
echo "================================================================"
echo "  CLUSTER READY"
echo "================================================================"
echo "  kube-vip VIP:  ${KUBE_VIP}"
echo "  Nodes:"
for i in "${!NODE_IPS[@]}"; do
  echo "    node-$((i+1)): ${NODE_IPS[$i]}"
done
echo ""
echo "  Next steps:"
echo "  1. export KUBECONFIG=$KUBECONFIG_FILE"
echo "  2. kubectl get nodes"
echo "  3. ./bootstrap/verify.sh"
echo "================================================================"
