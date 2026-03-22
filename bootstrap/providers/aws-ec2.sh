#!/usr/bin/env bash
# aws-ec2.sh — Provision N AWS EC2 instances and install a K3s HA cluster
# Called by bootstrap.sh after loading config.yaml
#
# HA requirements:
#   - nodes.count must be odd and >= 3 (enforced by bootstrap.sh)
#   - Minimum instance type: t3.small (t2.micro is NOT viable for K3s + workloads)
#   - kube-vip provides a floating VIP using the internal/private IPs
#   - K3s --cluster-init on instance-1, --server https://<VIP>:6443 on instances 2+
#   - kubeconfig points at the VIP, not a single instance IP
#
# NOTE: AWS free tier (t2.micro) is not supported — it does not have sufficient
#       resources to run K3s + Cilium + Crossplane + any workloads.
#       Minimum recommended: 3x t3.small (~$45/month) in the same VPC.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SOVEREIGN_CONFIG:-${SCRIPT_DIR}/../config.yaml}"

# Require aws CLI
if ! command -v aws &>/dev/null; then
  echo "ERROR: 'aws' CLI is required." >&2
  echo "  Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" >&2
  echo "  Then run: aws configure" >&2
  exit 1
fi

# Require yq
if ! command -v yq &>/dev/null; then
  echo "ERROR: 'yq' is required. Install with: brew install yq" >&2
  exit 1
fi

# Read AWS config
AWS_REGION="$(yq '.aws.region // "us-east-1"' "$CONFIG_FILE")"
INSTANCE_TYPE="$(yq '.nodes.serverType // "t3.small"' "$CONFIG_FILE")"
AMI_ID="$(yq '.aws.amiId // ""' "$CONFIG_FILE")"
INSTANCE_NAME_PREFIX="$(yq '.aws.instanceName // "sovereign"' "$CONFIG_FILE")"
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

# Enforce minimum instance type — t2.micro cannot run the platform
case "$INSTANCE_TYPE" in
  t2.micro|t2.nano|t1.micro)
    echo "ERROR: Instance type '$INSTANCE_TYPE' is not supported." >&2
    echo "  Minimum required: t3.small (2 vCPU, 2GB RAM)" >&2
    echo "  Recommended:      t3.medium or t3.large for production" >&2
    echo "  AWS free tier (t2.micro) does not have sufficient resources." >&2
    exit 1
    ;;
esac

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key not found: $SSH_KEY" >&2
  exit 1
fi

SSH_KEY_NAME="sovereign-$(basename "$SSH_KEY" | sed 's/[^a-zA-Z0-9]/-/g')"
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "==> [AWS EC2] Provisioning ${NODE_COUNT}-node HA cluster"
echo "    Instance type: $INSTANCE_TYPE"
echo "    Region:        $AWS_REGION"
echo "    Name prefix:   $INSTANCE_NAME_PREFIX"
echo "    K3s:           $K3S_VERSION"
echo "    kube-vip:      $KUBEVIP_VERSION"
echo ""

# ── Auto-detect Ubuntu 22.04 LTS AMI ────────────────────────────────────────
if [[ -z "$AMI_ID" || "$AMI_ID" == "null" || "$AMI_ID" == '""' ]]; then
  echo "==> Auto-detecting Ubuntu 22.04 LTS AMI in $AWS_REGION..."
  AMI_ID="$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters \
      "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
      "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)"
  echo "==> Found AMI: $AMI_ID"
fi

# ── Import SSH public key (idempotent) ───────────────────────────────────────
echo "==> Importing SSH public key as '$SSH_KEY_NAME'..."
if ! aws ec2 describe-key-pairs --key-names "$SSH_KEY_NAME" &>/dev/null; then
  if [[ -f "${SSH_KEY}.pub" ]]; then
    aws ec2 import-key-pair \
      --key-name "$SSH_KEY_NAME" \
      --public-key-material "fileb://${SSH_KEY}.pub"
  else
    echo "ERROR: SSH public key not found: ${SSH_KEY}.pub" >&2
    exit 1
  fi
else
  echo "==> Key pair '$SSH_KEY_NAME' already exists."
fi

# ── Create security group ────────────────────────────────────────────────────
SG_NAME="sovereign-k3s-sg"
SG_ID="$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || echo "None")"

if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
  echo "==> Creating security group '$SG_NAME'..."
  SG_ID="$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Sovereign Platform K3s security group" \
    --query 'GroupId' \
    --output text)"

  # Allow inter-node communication (all traffic within the SG)
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol all \
    --source-group "$SG_ID"

  # Allow SSH from anywhere (will be locked down by UFW + front door)
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0

  echo "==> Security group created: $SG_ID"
else
  echo "==> Security group '$SG_NAME' already exists: $SG_ID"
fi

# ── Provision all N instances ─────────────────────────────────────────────────
declare -a INSTANCE_IDS=()
declare -a NODE_IPS=()

for i in $(seq 1 "$NODE_COUNT"); do
  INSTANCE_NAME="${INSTANCE_NAME_PREFIX}-${i}"

  EXISTING_INSTANCE="$(aws ec2 describe-instances \
    --filters \
      "Name=tag:Name,Values=$INSTANCE_NAME" \
      "Name=instance-state-name,Values=running,pending,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || echo "None")"

  if [[ "$EXISTING_INSTANCE" != "None" && -n "$EXISTING_INSTANCE" ]]; then
    echo "==> Instance '$INSTANCE_NAME' already exists: $EXISTING_INSTANCE"
    INSTANCE_STATE="$(aws ec2 describe-instances \
      --instance-ids "$EXISTING_INSTANCE" \
      --query 'Reservations[0].Instances[0].State.Name' \
      --output text)"
    if [[ "$INSTANCE_STATE" == "stopped" ]]; then
      echo "  Starting stopped instance..."
      aws ec2 start-instances --instance-ids "$EXISTING_INSTANCE"
    fi
    INSTANCE_IDS+=("$EXISTING_INSTANCE")
  else
    echo "==> Launching EC2 instance $INSTANCE_NAME..."
    INSTANCE_ID="$(aws ec2 run-instances \
      --image-id "$AMI_ID" \
      --instance-type "$INSTANCE_TYPE" \
      --key-name "$SSH_KEY_NAME" \
      --security-group-ids "$SG_ID" \
      --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Project,Value=sovereign}]" \
      --query 'Instances[0].InstanceId' \
      --output text)"
    echo "  Instance launched: $INSTANCE_ID"
    INSTANCE_IDS+=("$INSTANCE_ID")
  fi
done

# ── Wait for all instances to be running ────────────────────────────────────
echo ""
echo "==> Waiting for all instances to be running..."
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
  echo "  Instance $INSTANCE_ID is running."
done

# ── Collect private IPs for kube-vip (VIP must be on same subnet) ───────────
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
  PRIVATE_IP="$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)"
  NODE_IPS+=("$PRIVATE_IP")
done

# Collect public IPs for SSH access
declare -a PUBLIC_IPS=()
for INSTANCE_ID in "${INSTANCE_IDS[@]}"; do
  PUBLIC_IP="$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)"
  PUBLIC_IPS+=("$PUBLIC_IP")
done

echo ""
echo "==> All instances provisioned:"
for i in "${!NODE_IPS[@]}"; do
  echo "    node-$((i+1)): private=${NODE_IPS[$i]}  public=${PUBLIC_IPS[$i]}"
  # Write public IPs to SOVEREIGN_NODELIST for hardening/frontdoor hooks
  if [[ -n "${SOVEREIGN_NODELIST:-}" ]]; then
    echo "${PUBLIC_IPS[$i]}" >> "$SOVEREIGN_NODELIST"
  fi
done
echo ""

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${SSH_KEY}")

# Wait for SSH on all nodes
for i in "${!PUBLIC_IPS[@]}"; do
  PUBLIC_IP="${PUBLIC_IPS[$i]}"
  echo "==> Waiting for SSH on node-$((i+1)) (${PUBLIC_IP})..."
  for attempt in $(seq 1 30); do
    if ssh "${SSH_OPTS[@]}" "ubuntu@${PUBLIC_IP}" "echo ok" &>/dev/null; then
      break
    fi
    echo "    SSH not ready (attempt $attempt/30)..."
    sleep 10
  done
done
echo ""

NODE1_PRIV="${NODE_IPS[0]}"
NODE1_PUB="${PUBLIC_IPS[0]}"

# ── Allocate kube-vip VIP (must be on same subnet as private IPs) ────────────
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
IFACE="$(ssh "${SSH_OPTS[@]}" "ubuntu@${NODE1_PUB}" \
  "ip -4 route show default | awk '{print \$5}' | head -1")"

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
ssh "${SSH_OPTS[@]}" "ubuntu@${NODE1_PUB}" \
  'sudo mkdir -p /var/lib/rancher/k3s/server/manifests'
cat /tmp/sovereign-kubevip-manifest.yaml | \
  ssh "${SSH_OPTS[@]}" "ubuntu@${NODE1_PUB}" \
  'sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip.yaml > /dev/null'

# shellcheck disable=SC2029
ssh "${SSH_OPTS[@]}" "ubuntu@${NODE1_PUB}" \
  "curl -sfL https://get.k3s.io | \
     INSTALL_K3S_VERSION=${K3S_VERSION} \
     sudo sh -s - server \
       --cluster-init \
       --write-kubeconfig-mode 644 \
       --tls-san ${KUBE_VIP} \
       --tls-san ${NODE1_PRIV} \
       --tls-san ${NODE1_PUB} \
       --tls-san ${DOMAIN}"

echo "  Waiting for K3s to start on node-1..."
for attempt in $(seq 1 30); do
  if ssh "${SSH_OPTS[@]}" "ubuntu@${NODE1_PUB}" "sudo k3s kubectl get nodes" &>/dev/null; then
    break
  fi
  echo "    Not ready yet (attempt $attempt/30)..."
  sleep 10
done
echo "==> K3s running on node-1"
echo ""

K3S_TOKEN="$(ssh "${SSH_OPTS[@]}" "ubuntu@${NODE1_PUB}" \
  "sudo cat /var/lib/rancher/k3s/server/node-token")"

# ── Join remaining nodes ──────────────────────────────────────────────────────
for i in $(seq 2 "$NODE_COUNT"); do
  PRIV_IP="${NODE_IPS[$((i-1))]}"
  PUB_IP="${PUBLIC_IPS[$((i-1))]}"
  echo "==> Joining node-${i} (${PUB_IP}) via VIP ${KUBE_VIP}..."

  ssh "${SSH_OPTS[@]}" "ubuntu@${PUB_IP}" \
    'sudo mkdir -p /var/lib/rancher/k3s/server/manifests'
  cat /tmp/sovereign-kubevip-manifest.yaml | \
    ssh "${SSH_OPTS[@]}" "ubuntu@${PUB_IP}" \
    'sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip.yaml > /dev/null'

  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "ubuntu@${PUB_IP}" \
    "curl -sfL https://get.k3s.io | \
       INSTALL_K3S_VERSION=${K3S_VERSION} \
       K3S_TOKEN=${K3S_TOKEN} \
       sudo sh -s - server \
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
  READY_COUNT="$(ssh "${SSH_OPTS[@]}" "ubuntu@${NODE1_PUB}" \
    "sudo k3s kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready'" || echo 0)"
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
KUBECONFIG_FILE="${KUBECONFIG_DIR}/sovereign-aws.yaml"

ssh "${SSH_OPTS[@]}" "ubuntu@${NODE1_PUB}" "sudo cat /etc/rancher/k3s/k3s.yaml" \
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
echo "  ESTIMATED MONTHLY COST (AWS EC2) — ${NODE_COUNT}-node cluster"
echo "================================================================"
echo "  NOTE: AWS free tier (t2.micro) is NOT supported."
echo "  Sovereign requires minimum t3.small (2 vCPU, 2GB RAM) per node."
echo ""
case "$INSTANCE_TYPE" in
  t3.small)
    echo "  ${NODE_COUNT}x t3.small  (2 vCPU, 2GB):   ~\$15/node  → \$$(( NODE_COUNT * 15 ))/month"
    echo "  3-node total:  ~\$45/month  [minimum — development only]"
    ;;
  t3.medium)
    echo "  ${NODE_COUNT}x t3.medium (2 vCPU, 4GB):   ~\$30/node  → \$$(( NODE_COUNT * 30 ))/month"
    echo "  3-node total:  ~\$90/month  [recommended for production]"
    ;;
  t3.large)
    echo "  ${NODE_COUNT}x t3.large  (2 vCPU, 8GB):   ~\$60/node  → \$$(( NODE_COUNT * 60 ))/month"
    echo "  3-node total:  ~\$180/month"
    ;;
  *)
    echo "  ${NODE_COUNT}x $INSTANCE_TYPE: see https://aws.amazon.com/ec2/pricing/"
    ;;
esac
echo ""
echo "  Additional costs: EBS storage (~\$0.10/GB/mo), data transfer."
echo ""
echo "  NOTE: Single-node and 2-node clusters are NOT supported."
echo ""

echo "================================================================"
echo "  CLUSTER READY"
echo "================================================================"
echo "  kube-vip VIP:  ${KUBE_VIP} (private)"
echo "  Nodes:"
for i in "${!NODE_IPS[@]}"; do
  echo "    node-$((i+1)): private=${NODE_IPS[$i]}  public=${PUBLIC_IPS[$i]}"
done
echo ""
echo "  Next steps:"
echo "  1. export KUBECONFIG=$KUBECONFIG_FILE"
echo "  2. kubectl get nodes"
echo "  3. ./bootstrap/verify.sh"
echo "================================================================"
