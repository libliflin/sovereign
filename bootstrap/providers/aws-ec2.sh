#!/usr/bin/env bash
# aws-ec2.sh — Provision an AWS EC2 instance and install K3s
# Called by bootstrap.sh after loading config.yaml
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
INSTANCE_TYPE="$(yq '.aws.instanceType // "t2.micro"' "$CONFIG_FILE")"
AMI_ID="$(yq '.aws.amiId // ""' "$CONFIG_FILE")"
INSTANCE_NAME="$(yq '.aws.instanceName // "sovereign-1"' "$CONFIG_FILE")"
SSH_KEY_PATH="${SOVEREIGN_SSH_KEY:-$(yq '.sshKeyPath // "~/.ssh/id_ed25519"' "$CONFIG_FILE")}"
DOMAIN="${SOVEREIGN_DOMAIN:-$(yq '.domain' "$CONFIG_FILE")}"
K3S_VERSION="$(yq '.k3sVersion // "v1.29.4+k3s1"' "$CONFIG_FILE")"

if [[ -z "$DOMAIN" || "$DOMAIN" == "null" ]]; then
  echo "ERROR: 'domain' is required in config.yaml" >&2
  exit 1
fi

# Expand tilde in SSH key path
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

if [[ ! -f "$SSH_KEY_PATH" ]]; then
  echo "ERROR: SSH key not found: $SSH_KEY_PATH" >&2
  exit 1
fi

SSH_KEY_NAME="sovereign-$(basename "$SSH_KEY_PATH" | sed 's/[^a-zA-Z0-9]/-/g')"

export AWS_DEFAULT_REGION="$AWS_REGION"

echo "==> [AWS EC2] Provisioning instance"
echo "    Instance type: $INSTANCE_TYPE"
echo "    Region:        $AWS_REGION"
echo "    Name:          $INSTANCE_NAME"
echo ""

# Auto-detect latest Ubuntu 22.04 LTS AMI if not specified
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

# Import SSH public key to AWS (idempotent)
echo "==> Importing SSH public key as key pair '$SSH_KEY_NAME'..."
if ! aws ec2 describe-key-pairs --key-names "$SSH_KEY_NAME" &>/dev/null; then
  if [[ -f "${SSH_KEY_PATH}.pub" ]]; then
    aws ec2 import-key-pair \
      --key-name "$SSH_KEY_NAME" \
      --public-key-material "fileb://${SSH_KEY_PATH}.pub"
  else
    echo "ERROR: SSH public key not found: ${SSH_KEY_PATH}.pub" >&2
    exit 1
  fi
else
  echo "==> Key pair '$SSH_KEY_NAME' already exists."
fi

# Create security group (idempotent)
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

  # Allow SSH
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0

  # Allow HTTPS
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 443 --cidr 0.0.0.0/0

  # Allow HTTP (for cert-manager ACME)
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0

  # Allow K3s API
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 6443 --cidr 0.0.0.0/0

  echo "==> Security group created: $SG_ID"
else
  echo "==> Security group '$SG_NAME' already exists: $SG_ID"
fi

# Check if instance already exists
EXISTING_INSTANCE="$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=$INSTANCE_NAME" \
    "Name=instance-state-name,Values=running,pending,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text 2>/dev/null || echo "None")"

if [[ "$EXISTING_INSTANCE" != "None" && -n "$EXISTING_INSTANCE" ]]; then
  echo "==> Instance '$INSTANCE_NAME' already exists: $EXISTING_INSTANCE"
  # Start if stopped
  INSTANCE_STATE="$(aws ec2 describe-instances \
    --instance-ids "$EXISTING_INSTANCE" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)"
  if [[ "$INSTANCE_STATE" == "stopped" ]]; then
    echo "==> Starting stopped instance..."
    aws ec2 start-instances --instance-ids "$EXISTING_INSTANCE"
  fi
  INSTANCE_ID="$EXISTING_INSTANCE"
else
  echo "==> Launching EC2 instance..."
  INSTANCE_ID="$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$SSH_KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Project,Value=sovereign}]" \
    --query 'Instances[0].InstanceId' \
    --output text)"
  echo "==> Instance launched: $INSTANCE_ID"
fi

# Wait for instance to be running
echo "==> Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "==> Instance is running."

# Get public IP
SERVER_IP="$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)"

echo "==> Instance IP: $SERVER_IP"

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${SSH_KEY_PATH}")

# Wait for SSH to be ready
echo "==> Waiting for SSH to be ready..."
for i in $(seq 1 30); do
  if ssh "${SSH_OPTS[@]}" "ubuntu@${SERVER_IP}" "echo ok" &>/dev/null; then
    break
  fi
  echo "    SSH not ready yet (attempt $i/30)..."
  sleep 10
done

# Check if K3s is already installed
if ssh "${SSH_OPTS[@]}" "ubuntu@${SERVER_IP}" "command -v k3s" &>/dev/null; then
  echo "==> K3s already installed, skipping."
else
  echo "==> Installing K3s ${K3S_VERSION}..."
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "ubuntu@${SERVER_IP}" \
    "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} sh -s - \
      --write-kubeconfig-mode 644 \
      --tls-san ${SERVER_IP} \
      --tls-san ${DOMAIN}"

  echo "==> Waiting for K3s to start..."
  for i in $(seq 1 20); do
    if ssh "${SSH_OPTS[@]}" "ubuntu@${SERVER_IP}" "sudo kubectl get nodes" &>/dev/null; then
      break
    fi
    echo "    Not ready yet (attempt $i/20)..."
    sleep 10
  done
fi

# Retrieve kubeconfig
echo "==> Fetching kubeconfig..."
KUBECONFIG_DIR="${HOME}/.kube"
mkdir -p "$KUBECONFIG_DIR"
KUBECONFIG_FILE="${KUBECONFIG_DIR}/sovereign-aws.yaml"

ssh "${SSH_OPTS[@]}" "ubuntu@${SERVER_IP}" "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/${SERVER_IP}/g" \
  > "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE"
echo "==> kubeconfig saved to: $KUBECONFIG_FILE"
echo ""
echo "    To use:  export KUBECONFIG=$KUBECONFIG_FILE"
echo ""

# Cost estimate
echo "================================================================"
echo "  ESTIMATED MONTHLY COST (AWS EC2)"
echo "================================================================"
case "$INSTANCE_TYPE" in
  t2.micro)  echo "  FREE TIER: t2.micro — 750 hrs/month free for first 12 months" ;;
  t2.small)  echo "  ~\$17/month  (t2.small — 1 vCPU, 2GB RAM)" ;;
  t3.micro)  echo "  ~\$8/month   (t3.micro — 2 vCPU, 1GB RAM)" ;;
  t3.small)  echo "  ~\$15/month  (t3.small — 2 vCPU, 2GB RAM)" ;;
  t3.medium) echo "  ~\$30/month  (t3.medium — 2 vCPU, 4GB RAM)" ;;
  *)         echo "  See https://aws.amazon.com/ec2/pricing/ for $INSTANCE_TYPE pricing" ;;
esac
echo "  Note: EBS storage (~\$0.10/GB/mo), data transfer, and EIP also billed."
echo ""

# DNS instructions
echo "================================================================"
echo "  CLOUDFLARE DNS SETUP"
echo "================================================================"
echo "  Add a wildcard A record in Cloudflare DNS:"
echo ""
echo "    Type:  A"
echo "    Name:  *.${DOMAIN}"
echo "    Value: ${SERVER_IP}"
echo "    TTL:   Auto"
echo "    Proxy: DNS only (grey cloud) — NOT proxied initially"
echo ""
echo "  Also add a root A record:"
echo "    Type:  A"
echo "    Name:  ${DOMAIN}"
echo "    Value: ${SERVER_IP}"
echo ""
echo "================================================================"
echo "  NEXT STEPS"
echo "================================================================"
echo "  1. Set Cloudflare DNS as shown above"
echo "  2. export KUBECONFIG=$KUBECONFIG_FILE"
echo "  3. kubectl get nodes   # verify cluster is Ready"
echo "  4. ./bootstrap/verify.sh"
echo "================================================================"
