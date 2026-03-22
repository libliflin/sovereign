# AWS EC2 — Provider Guide

AWS EC2 is a supported Sovereign provider. Sovereign requires a **3-node HA cluster**
minimum — single-node deployments are not supported.

The minimum supported EC2 instance type is **t3.small** (2 vCPU, 2 GB RAM). The recommended
instance for production is **t3.medium** (2 vCPU, 4 GB RAM).

## Estimated Cost (3-Node HA Cluster)

| Instance Type | vCPU | RAM  | Per Node/Month | 3-Node Total |
|---------------|------|------|----------------|--------------|
| t3.small      | 2    | 2 GB | ~$15           | **~$45/month** (development) |
| t3.medium     | 2    | 4 GB | ~$30           | **~$90/month** ✓ recommended |
| t3.large      | 2    | 8 GB | ~$60           | **~$180/month** |
| t3.xlarge     | 4    | 16 GB| ~$120          | **~$360/month** |

**Additional charges:** EBS storage (~$0.10/GB/month), data transfer, and Elastic IP
(free while running, $0.005/hr when stopped).

Recommended minimum for production: **3x t3.medium** (~$90/month total).

## Prerequisites

- An AWS account: <https://aws.amazon.com/>
- `aws` CLI installed and configured
- `yq` YAML parser installed
- An SSH key pair (`~/.ssh/id_ed25519` by default)

### Install AWS CLI

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install
```

### Install yq

```bash
# macOS
brew install yq

# Linux
sudo snap install yq
```

## Step-by-Step Setup

### 1. Create an AWS account and configure CLI

1. Go to <https://aws.amazon.com/> → **Create an AWS Account**
2. In AWS Console → **IAM** → create a user with **AmazonEC2FullAccess** and **AmazonVPCFullAccess**
3. Create an Access Key for that user

```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: us-east-1
# Default output format: json
```

### 2. Configure Sovereign

```bash
cp bootstrap/config.yaml.example bootstrap/config.yaml
```

Edit `bootstrap/config.yaml`:

```yaml
domain: "your-domain.com"
provider: "aws-ec2"
sshKeyPath: "~/.ssh/id_ed25519"

nodes:
  count: 3          # minimum — must be odd and >= 3
  serverType: "t3.medium"   # recommended for production

# Optional: specify the kube-vip VIP (auto-derived from node-1 subnet if omitted)
# kubeVip:
#   vip: "10.0.1.100"   # must be an unused IP on the same subnet as your instances

aws:
  region: "us-east-1"
  instanceName: "sovereign"   # nodes will be sovereign-1, sovereign-2, sovereign-3
  # amiId: ""                  # leave empty to auto-detect Ubuntu 22.04 LTS
```

### 3. Run bootstrap

```bash
./bootstrap/bootstrap.sh
```

This will:
1. Auto-detect the latest Ubuntu 22.04 LTS AMI in your region
2. Import your SSH public key to AWS
3. Create a security group allowing inter-node communication + SSH
4. Launch `nodes.count` EC2 instances (sovereign-1, sovereign-2, sovereign-3)
5. Install kube-vip on each node for a floating API server VIP
6. Install K3s with `--cluster-init` + embedded etcd on node-1
7. Join nodes 2+ to the cluster via the kube-vip VIP
8. Wait for all nodes to be Ready
9. Fetch and save kubeconfig (pointing at kube-vip VIP) to `~/.kube/sovereign-aws.yaml`

### 4. Verify the cluster

```bash
export KUBECONFIG=~/.kube/sovereign-aws.yaml
kubectl get nodes
# NAME             STATUS   ROLES                       AGE   VERSION
# sovereign-1      Ready    control-plane,etcd,master   2m    v1.29.4+k3s1
# sovereign-2      Ready    control-plane,etcd,master   1m    v1.29.4+k3s1
# sovereign-3      Ready    control-plane,etcd,master   1m    v1.29.4+k3s1

./bootstrap/verify.sh --vip <your-kube-vip-address>
```

## Adding Nodes

To scale out the cluster (must maintain odd count):

1. Update `nodes.count: 5` in `config.yaml`
2. Re-run `./bootstrap/bootstrap.sh` — it's idempotent and will provision the new nodes
3. The new nodes auto-join via the kube-vip VIP

## Replacing a Failed Node

```bash
# 1. Cordon the failed node
kubectl cordon sovereign-2

# 2. Drain workloads (etcd will continue with 2/3 healthy nodes)
kubectl drain sovereign-2 --ignore-daemonsets --delete-emptydir-data

# 3. Delete from the cluster
kubectl delete node sovereign-2

# 4. Terminate the failed EC2 instance
aws ec2 terminate-instances --instance-ids <instance-id>

# 5. Re-run bootstrap to provision a replacement node
./bootstrap/bootstrap.sh
```

## Elastic IP for VIP Stability

The kube-vip VIP is a private IP — it floats across your VPC and doesn't need an EIP.
However, if you want SSH access to individual nodes without the tunnel, assign EIPs:

```bash
# Allocate and associate an EIP for node-1
EIP_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
aws ec2 associate-address \
  --instance-id <instance-1-id> \
  --allocation-id "$EIP_ID"
```

## Cleanup

```bash
# Terminate all instances
for i in 1 2 3; do
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=sovereign-${i}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
done

# Release EIPs (if allocated)
aws ec2 release-address --allocation-id <eip-allocation-id>

# Delete security group (after instances are terminated)
aws ec2 delete-security-group --group-name sovereign-k3s-sg
```

## Troubleshooting

**Permission denied (publickey):** Ubuntu 22.04 AMIs use `ubuntu` user, not `root`.
The bootstrap script automatically uses `ubuntu@<ip>`.

**AMI not found:** The auto-detection queries Canonical's official AMI catalogue (owner 099720109477).
You can specify a manual AMI ID in `config.yaml` under `aws.amiId`.

**Node fails to join:** Check the kube-vip VIP is reachable on the private subnet.
Verify with: `ssh ubuntu@<node-ip> "curl -sk https://<vip>:6443/healthz"`

**Instances take time to SSH:** EC2 instances typically take 60–90 seconds to boot.
The script retries SSH every 10 seconds for up to 5 minutes.
