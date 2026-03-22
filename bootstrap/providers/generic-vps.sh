#!/usr/bin/env bash
# generic-vps.sh — Install K3s HA cluster on existing Ubuntu 22.04 servers via SSH
# Called by bootstrap.sh after loading config.yaml
#
# Usage:
#   Set genericVps.nodeIps in config.yaml as a comma-separated list of IPs:
#     genericVps:
#       nodeIps: "10.0.0.1,10.0.0.2,10.0.0.3"
#       sshUser: root
#       sshKeyPath: ~/.ssh/id_ed25519
#
# HA requirements:
#   - nodeIps must contain nodes.count IPs (validated by bootstrap.sh)
#   - kube-vip provides a floating VIP for the K3s API server
#   - K3s --cluster-init on node-1, --server https://<VIP>:6443 on nodes 2+
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SOVEREIGN_CONFIG:-${SCRIPT_DIR}/../config.yaml}"

# Require yq
if ! command -v yq &>/dev/null; then
  echo "ERROR: 'yq' is required. Install with: brew install yq" >&2
  exit 1
fi

# Read generic VPS config
NODE_IPS_CSV="$(yq '.genericVps.nodeIps' "$CONFIG_FILE")"
SSH_USER="$(yq '.genericVps.sshUser // "root"' "$CONFIG_FILE")"
DOMAIN="${SOVEREIGN_DOMAIN:-$(yq '.domain' "$CONFIG_FILE")}"
K3S_VERSION="$(yq '.k3sVersion // "v1.29.4+k3s1"' "$CONFIG_FILE")"
SSH_KEY="${SOVEREIGN_SSH_KEY:-$(yq '.sshKeyPath // "~/.ssh/id_ed25519"' "$CONFIG_FILE")}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"
KUBEVIP_VERSION="v0.7.2"

if [[ -z "$NODE_IPS_CSV" || "$NODE_IPS_CSV" == "null" ]]; then
  echo "ERROR: 'genericVps.nodeIps' is required in config.yaml" >&2
  echo "  Example: nodeIps: \"10.0.0.1,10.0.0.2,10.0.0.3\"" >&2
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key not found: $SSH_KEY" >&2
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${SSH_KEY}")

# Parse comma-separated IPs into an array
IFS=',' read -ra NODE_IPS <<< "$NODE_IPS_CSV"
NODE_COUNT="${#NODE_IPS[@]}"

echo "==> [Generic VPS] Preparing ${NODE_COUNT}-node HA K3s cluster"
echo "    SSH user:    $SSH_USER"
echo "    K3s:         $K3S_VERSION"
echo "    kube-vip:    $KUBEVIP_VERSION"
echo "    Domain:      $DOMAIN"
echo ""

# ── Verify SSH connectivity to all nodes ────────────────────────────────────
for i in "${!NODE_IPS[@]}"; do
  NODE_IP="${NODE_IPS[$i]}"
  echo "==> Testing SSH to node-$((i+1)): ${SSH_USER}@${NODE_IP}..."
  if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE_IP}" "echo 'SSH OK'" 2>/dev/null; then
    echo "ERROR: Cannot connect to ${SSH_USER}@${NODE_IP}" >&2
    echo "  Verify the IP address and SSH key are correct." >&2
    exit 1
  fi
  # Write to SOVEREIGN_NODELIST for bootstrap.sh to pick up
  if [[ -n "${SOVEREIGN_NODELIST:-}" ]]; then
    echo "$NODE_IP" >> "$SOVEREIGN_NODELIST"
  fi
done
echo ""

NODE1_IP="${NODE_IPS[0]}"

# ── Allocate kube-vip VIP ────────────────────────────────────────────────────
KUBE_VIP="$(yq '.kubeVip.vip // ""' "$CONFIG_FILE")"
if [[ -z "$KUBE_VIP" || "$KUBE_VIP" == "null" ]]; then
  KUBE_VIP="$(echo "$NODE1_IP" | cut -d. -f1-3).100"
  echo "==> kube-vip VIP auto-derived: ${KUBE_VIP}"
  echo "    (Set kubeVip.vip in config.yaml to override)"
else
  echo "==> kube-vip VIP from config: ${KUBE_VIP}"
fi
echo ""

# ── Build kube-vip static Pod manifest ──────────────────────────────────────
IFACE="$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE1_IP}" \
  "ip -4 route show default | awk '{print \$5}' | head -1")"
echo "==> Network interface: ${IFACE}"

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

# ── Install K3s on node-1 with --cluster-init ────────────────────────────────
echo "==> Installing K3s on node-1 (${NODE1_IP}) with --cluster-init..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE1_IP}" \
  'mkdir -p /var/lib/rancher/k3s/server/manifests'
cat /tmp/sovereign-kubevip-manifest.yaml | \
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE1_IP}" \
  'cat > /var/lib/rancher/k3s/server/manifests/kube-vip.yaml'

# shellcheck disable=SC2029
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE1_IP}" \
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
  if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE1_IP}" "k3s kubectl get nodes" &>/dev/null; then
    break
  fi
  echo "    Not ready yet (attempt $attempt/30)..."
  sleep 10
done
echo "==> K3s running on node-1"
echo ""

# ── Get join token ────────────────────────────────────────────────────────────
K3S_TOKEN="$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE1_IP}" \
  "cat /var/lib/rancher/k3s/server/node-token")"

# ── Join remaining nodes ──────────────────────────────────────────────────────
for i in $(seq 2 "$NODE_COUNT"); do
  NODE_IP="${NODE_IPS[$((i-1))]}"
  echo "==> Joining node-${i} (${NODE_IP}) via VIP ${KUBE_VIP}..."

  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE_IP}" \
    'mkdir -p /var/lib/rancher/k3s/server/manifests'
  cat /tmp/sovereign-kubevip-manifest.yaml | \
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE_IP}" \
    'cat > /var/lib/rancher/k3s/server/manifests/kube-vip.yaml'

  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE_IP}" \
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

# ── Verify all nodes are Ready ───────────────────────────────────────────────
echo "==> Waiting for all ${NODE_COUNT} nodes to be Ready..."
READY_COUNT=0
for attempt in $(seq 1 40); do
  READY_COUNT="$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE1_IP}" \
    "k3s kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready'" || echo 0)"
  if [[ "$READY_COUNT" -ge "$NODE_COUNT" ]]; then
    echo "==> All ${NODE_COUNT} nodes are Ready."
    break
  fi
  echo "    ${READY_COUNT}/${NODE_COUNT} nodes Ready (attempt $attempt/40)..."
  sleep 10
done

if [[ "$READY_COUNT" -lt "$NODE_COUNT" ]]; then
  echo "ERROR: Only ${READY_COUNT}/${NODE_COUNT} nodes became Ready." >&2
  exit 1
fi
echo ""

# ── Retrieve kubeconfig pointing at VIP ──────────────────────────────────────
echo "==> Fetching kubeconfig (pointing at VIP: ${KUBE_VIP})..."
KUBECONFIG_DIR="${HOME}/.kube"
mkdir -p "$KUBECONFIG_DIR"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/sovereign-vps.yaml"

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE1_IP}" "cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/${KUBE_VIP}/g" \
  > "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE"
echo "==> kubeconfig saved to: $KUBECONFIG_FILE"
echo "    Server: https://${KUBE_VIP}:6443"
echo ""
echo "    To use:  export KUBECONFIG=$KUBECONFIG_FILE"
echo ""

# ── Cost estimate ────────────────────────────────────────────────────────────
echo "================================================================"
echo "  ESTIMATED MONTHLY COST — ${NODE_COUNT}-node HA cluster"
echo "================================================================"
echo "  Typical pricing for Ubuntu 22.04 VPS nodes:"
echo ""
echo "    Vultr   2 vCPU / 4GB:    ~\$24/node  → \$72/month for 3 nodes"
echo "    Linode  2 vCPU / 4GB:    ~\$20/node  → \$60/month for 3 nodes"
echo "    Vultr   4 vCPU / 8GB:    ~\$48/node  → \$144/month for 3 nodes"
echo "    Linode  4 vCPU / 8GB:    ~\$40/node  → \$120/month for 3 nodes"
echo ""
echo "  NOTE: Single-node and 2-node clusters are NOT supported."
echo "  Minimum is 3 nodes (etcd quorum + Ceph replication factor 3)."
echo ""

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
