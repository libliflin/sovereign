#!/usr/bin/env bash
# digitalocean.sh — Provision N DigitalOcean Droplets and install a K3s HA cluster
# Called by bootstrap.sh after loading config.yaml
#
# HA requirements:
#   - nodes.count must be odd and >= 3 (enforced by bootstrap.sh)
#   - kube-vip provides a floating VIP using private (VPC) IPs
#   - K3s --cluster-init on droplet-1, --server https://<VIP>:6443 on droplets 2+
#   - kubeconfig points at the VIP, not a single droplet IP
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SOVEREIGN_CONFIG:-${SCRIPT_DIR}/../config.yaml}"

# Require doctl CLI
if ! command -v doctl &>/dev/null; then
  echo "ERROR: 'doctl' CLI is required." >&2
  echo "  Install: brew install doctl  (macOS)" >&2
  echo "  Then run: doctl auth init" >&2
  exit 1
fi

# Require yq
if ! command -v yq &>/dev/null; then
  echo "ERROR: 'yq' is required. Install with: brew install yq" >&2
  exit 1
fi

# Read DigitalOcean config
DO_SIZE="$(yq '.nodes.serverType // "s-2vcpu-4gb"' "$CONFIG_FILE")"
DO_REGION="$(yq '.digitalocean.region // "nyc3"' "$CONFIG_FILE")"
DROPLET_NAME_PREFIX="$(yq '.digitalocean.dropletName // "sovereign"' "$CONFIG_FILE")"
SSH_KEY="${SOVEREIGN_SSH_KEY:-$(yq '.sshKeyPath // "~/.ssh/id_ed25519"' "$CONFIG_FILE")}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"
DOMAIN="${SOVEREIGN_DOMAIN:-$(yq '.domain' "$CONFIG_FILE")}"
K3S_VERSION="$(yq '.k3sVersion // "v1.29.4+k3s1"' "$CONFIG_FILE")"
NODE_COUNT="${NODE_COUNT:-$(yq '.nodes.count // 3' "$CONFIG_FILE")}"
KUBEVIP_VERSION="v0.7.2"

if [[ -z "$DOMAIN" || "$DOMAIN" == "null" ]]; then
  echo "ERROR: 'domain' is required in config.yaml" >&2
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key not found: $SSH_KEY" >&2
  exit 1
fi

SSH_KEY_PUB="${SSH_KEY}.pub"
if [[ ! -f "$SSH_KEY_PUB" ]]; then
  echo "ERROR: SSH public key not found: $SSH_KEY_PUB" >&2
  exit 1
fi

echo "==> [DigitalOcean] Provisioning ${NODE_COUNT}-node HA cluster"
echo "    Droplet size:  $DO_SIZE"
echo "    Region:        $DO_REGION"
echo "    Name prefix:   $DROPLET_NAME_PREFIX"
echo "    K3s:           $K3S_VERSION"
echo "    kube-vip:      $KUBEVIP_VERSION"
echo ""

# ── Upload SSH key (idempotent by fingerprint) ────────────────────────────────
SSH_FINGERPRINT="$(ssh-keygen -lf "$SSH_KEY_PUB" | awk '{print $2}')"
DO_KEY_ID="$(doctl compute ssh-key list --format FingerPrint,ID --no-header 2>/dev/null \
  | grep "$SSH_FINGERPRINT" | awk '{print $2}' || true)"

if [[ -z "$DO_KEY_ID" ]]; then
  echo "==> Uploading SSH key to DigitalOcean..."
  DO_KEY_ID="$(doctl compute ssh-key import "sovereign-key" \
    --public-key-file "$SSH_KEY_PUB" \
    --format ID \
    --no-header)"
  echo "==> SSH key imported: $DO_KEY_ID"
else
  echo "==> SSH key already in DigitalOcean: $DO_KEY_ID"
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${SSH_KEY}")

# ── Create VPC for private networking ────────────────────────────────────────
VPC_NAME="sovereign-vpc-${DO_REGION}"
VPC_ID="$(doctl vpcs list --format Name,ID --no-header 2>/dev/null \
  | grep "^${VPC_NAME} " | awk '{print $2}' || true)"

if [[ -z "$VPC_ID" ]]; then
  echo "==> Creating VPC '${VPC_NAME}'..."
  VPC_ID="$(doctl vpcs create \
    --name "$VPC_NAME" \
    --region "$DO_REGION" \
    --format ID \
    --no-header)"
  echo "==> VPC created: $VPC_ID"
else
  echo "==> VPC already exists: $VPC_ID"
fi

# ── Provision all N droplets ──────────────────────────────────────────────────
declare -a DROPLET_IDS=()
declare -a NODE_PUBLIC_IPS=()

for i in $(seq 1 "$NODE_COUNT"); do
  DROPLET_NAME="${DROPLET_NAME_PREFIX}-${i}"

  EXISTING_ID="$(doctl compute droplet list --format Name,ID --no-header 2>/dev/null \
    | grep "^${DROPLET_NAME} " | awk '{print $2}' || true)"

  if [[ -n "$EXISTING_ID" ]]; then
    echo "==> Droplet '$DROPLET_NAME' already exists: $EXISTING_ID"
    DROPLET_IDS+=("$EXISTING_ID")
  else
    echo "==> Creating Droplet '$DROPLET_NAME'..."
    DROPLET_ID="$(doctl compute droplet create "$DROPLET_NAME" \
      --image ubuntu-22-04-x64 \
      --size "$DO_SIZE" \
      --region "$DO_REGION" \
      --vpc-uuid "$VPC_ID" \
      --ssh-keys "$DO_KEY_ID" \
      --enable-private-networking \
      --wait \
      --format ID \
      --no-header)"
    echo "  Droplet created: $DROPLET_ID"
    DROPLET_IDS+=("$DROPLET_ID")
  fi
done

# ── Collect public and private IPs ────────────────────────────────────────────
declare -a NODE_PRIVATE_IPS=()

for DROPLET_ID in "${DROPLET_IDS[@]}"; do
  PUBLIC_IP="$(doctl compute droplet get "$DROPLET_ID" \
    --format PublicIPv4 --no-header)"
  PRIVATE_IP="$(doctl compute droplet get "$DROPLET_ID" \
    --format PrivateIPv4 --no-header)"

  # Wait for IP if not yet assigned
  if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "null" ]]; then
    for attempt in $(seq 1 20); do
      PUBLIC_IP="$(doctl compute droplet get "$DROPLET_ID" \
        --format PublicIPv4 --no-header 2>/dev/null || echo "")"
      if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "null" ]]; then
        break
      fi
      echo "    Waiting for IP (attempt $attempt/20)..."
      sleep 5
    done
  fi

  NODE_PUBLIC_IPS+=("$PUBLIC_IP")
  NODE_PRIVATE_IPS+=("$PRIVATE_IP")
done

echo ""
echo "==> All droplets provisioned:"
for i in "${!NODE_PUBLIC_IPS[@]}"; do
  echo "    node-$((i+1)): public=${NODE_PUBLIC_IPS[$i]}  private=${NODE_PRIVATE_IPS[$i]}"
  # Write public IPs to SOVEREIGN_NODELIST for hardening/frontdoor hooks
  if [[ -n "${SOVEREIGN_NODELIST:-}" ]]; then
    echo "${NODE_PUBLIC_IPS[$i]}" >> "$SOVEREIGN_NODELIST"
  fi
done
echo ""

# Wait for SSH on all nodes
for i in "${!NODE_PUBLIC_IPS[@]}"; do
  PUBLIC_IP="${NODE_PUBLIC_IPS[$i]}"
  echo "==> Waiting for SSH on node-$((i+1)) (${PUBLIC_IP})..."
  for attempt in $(seq 1 30); do
    if ssh "${SSH_OPTS[@]}" "root@${PUBLIC_IP}" "echo ok" &>/dev/null; then
      break
    fi
    echo "    SSH not ready (attempt $attempt/30)..."
    sleep 10
  done
done
echo ""

NODE1_PUB="${NODE_PUBLIC_IPS[0]}"
NODE1_PRIV="${NODE_PRIVATE_IPS[0]}"

# ── Allocate kube-vip VIP (must be on same VPC subnet) ───────────────────────
KUBE_VIP="$(yq '.kubeVip.vip // ""' "$CONFIG_FILE")"
if [[ -z "$KUBE_VIP" || "$KUBE_VIP" == "null" ]]; then
  # Auto-derive: same /24 as node-1 private IP, last octet 100
  KUBE_VIP="$(echo "$NODE1_PRIV" | cut -d. -f1-3).100"
  echo "==> kube-vip VIP auto-derived from private subnet: ${KUBE_VIP}"
  echo "    (Set kubeVip.vip in config.yaml to override)"
else
  echo "==> kube-vip VIP from config: ${KUBE_VIP}"
fi
echo ""

# ── Build kube-vip manifest ──────────────────────────────────────────────────
# Use the private network interface (eth1 on DigitalOcean with private networking)
# shellcheck disable=SC2029
IFACE="$(ssh "${SSH_OPTS[@]}" "root@${NODE1_PUB}" \
  "ip -4 addr show | grep '${NODE1_PRIV}' | awk '{print \$NF}' | head -1 || \
   ip -4 route show default | awk '{print \$5}' | head -1")"
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
echo "==> Installing K3s on node-1 (${NODE1_PUB}) with --cluster-init..."
ssh "${SSH_OPTS[@]}" "root@${NODE1_PUB}" \
  'mkdir -p /var/lib/rancher/k3s/server/manifests'
cat /tmp/sovereign-kubevip-manifest.yaml | \
  ssh "${SSH_OPTS[@]}" "root@${NODE1_PUB}" \
  'cat > /var/lib/rancher/k3s/server/manifests/kube-vip.yaml'

# shellcheck disable=SC2029
ssh "${SSH_OPTS[@]}" "root@${NODE1_PUB}" \
  "curl -sfL https://get.k3s.io | \
     INSTALL_K3S_VERSION=${K3S_VERSION} \
     sh -s - server \
       --cluster-init \
       --write-kubeconfig-mode 644 \
       --tls-san ${KUBE_VIP} \
       --tls-san ${NODE1_PRIV} \
       --tls-san ${NODE1_PUB} \
       --tls-san ${DOMAIN}"

echo "  Waiting for K3s to start on node-1..."
for attempt in $(seq 1 30); do
  if ssh "${SSH_OPTS[@]}" "root@${NODE1_PUB}" "k3s kubectl get nodes" &>/dev/null; then
    break
  fi
  echo "    Not ready yet (attempt $attempt/30)..."
  sleep 10
done
echo "==> K3s running on node-1"
echo ""

K3S_TOKEN="$(ssh "${SSH_OPTS[@]}" "root@${NODE1_PUB}" \
  "cat /var/lib/rancher/k3s/server/node-token")"

# ── Join remaining droplets ──────────────────────────────────────────────────
for i in $(seq 2 "$NODE_COUNT"); do
  PUB_IP="${NODE_PUBLIC_IPS[$((i-1))]}"
  PRIV_IP="${NODE_PRIVATE_IPS[$((i-1))]}"
  echo "==> Joining node-${i} (${PUB_IP}) via VIP ${KUBE_VIP}..."

  ssh "${SSH_OPTS[@]}" "root@${PUB_IP}" \
    'mkdir -p /var/lib/rancher/k3s/server/manifests'
  cat /tmp/sovereign-kubevip-manifest.yaml | \
    ssh "${SSH_OPTS[@]}" "root@${PUB_IP}" \
    'cat > /var/lib/rancher/k3s/server/manifests/kube-vip.yaml'

  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "root@${PUB_IP}" \
    "curl -sfL https://get.k3s.io | \
       INSTALL_K3S_VERSION=${K3S_VERSION} \
       K3S_TOKEN=${K3S_TOKEN} \
       sh -s - server \
         --server https://${KUBE_VIP}:6443 \
         --write-kubeconfig-mode 644 \
         --tls-san ${KUBE_VIP} \
         --tls-san ${PRIV_IP} \
         --tls-san ${PUB_IP} \
         --tls-san ${DOMAIN}"

  echo "  Node-${i} joined."
done
echo ""

# ── Verify all nodes Ready ───────────────────────────────────────────────────
echo "==> Waiting for all ${NODE_COUNT} nodes to be Ready..."
READY_COUNT=0
for attempt in $(seq 1 40); do
  READY_COUNT="$(ssh "${SSH_OPTS[@]}" "root@${NODE1_PUB}" \
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
KUBECONFIG_FILE="${KUBECONFIG_DIR}/sovereign-do.yaml"

ssh "${SSH_OPTS[@]}" "root@${NODE1_PUB}" "cat /etc/rancher/k3s/k3s.yaml" \
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
echo "  ESTIMATED MONTHLY COST (DigitalOcean) — ${NODE_COUNT}-node cluster"
echo "================================================================"
case "$DO_SIZE" in
  s-1vcpu-2gb)
    echo "  ${NODE_COUNT}x s-1vcpu-2gb  (1 vCPU, 2GB):   ~\$12/node  → \$$(( NODE_COUNT * 12 ))/month"
    echo "  3-node total:  ~\$36/month  [development only — underpowered]"
    ;;
  s-2vcpu-4gb)
    echo "  ${NODE_COUNT}x s-2vcpu-4gb  (2 vCPU, 4GB):   ~\$24/node  → \$$(( NODE_COUNT * 24 ))/month"
    echo "  3-node total:  ~\$72/month  [recommended minimum for production]"
    ;;
  s-4vcpu-8gb)
    echo "  ${NODE_COUNT}x s-4vcpu-8gb  (4 vCPU, 8GB):   ~\$48/node  → \$$(( NODE_COUNT * 48 ))/month"
    echo "  3-node total:  ~\$144/month  [recommended for production]"
    ;;
  *)
    echo "  ${NODE_COUNT}x $DO_SIZE: see https://www.digitalocean.com/pricing"
    ;;
esac
echo ""
echo "  NOTE: Single-node and 2-node clusters are NOT supported."
echo "  Minimum is 3 nodes (etcd quorum + Ceph replication factor 3)."
echo ""

echo "================================================================"
echo "  CLUSTER READY"
echo "================================================================"
echo "  kube-vip VIP:  ${KUBE_VIP} (private VPC)"
echo "  Nodes:"
for i in "${!NODE_PUBLIC_IPS[@]}"; do
  echo "    node-$((i+1)): public=${NODE_PUBLIC_IPS[$i]}  private=${NODE_PRIVATE_IPS[$i]}"
done
echo ""
echo "  Next steps:"
echo "  1. export KUBECONFIG=$KUBECONFIG_FILE"
echo "  2. kubectl get nodes"
echo "  3. ./bootstrap/verify.sh"
echo "================================================================"
