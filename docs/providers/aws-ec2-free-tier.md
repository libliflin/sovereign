# AWS EC2 Free Tier — Provider Guide

AWS offers a free tier for new accounts: 750 hours/month of `t2.micro` for the first
12 months. This is enough to run a minimal Sovereign cluster at zero cost.

## Estimated Cost

| Instance Type | vCPU | RAM  | Monthly (USD)         |
|---------------|------|------|-----------------------|
| t2.micro      | 1    | 1 GB | **FREE** (12 months, new accounts) |
| t3.micro      | 2    | 1 GB | ~$8                   |
| t3.small      | 2    | 2 GB | ~$15 ✓ recommended    |
| t3.medium     | 2    | 4 GB | ~$30                  |

**Note:** Additional charges apply for EBS storage (~$0.10/GB/month), data transfer,
and Elastic IP. For a t2.micro free tier node with 20 GB EBS, expect ~$2–3/month
(or $0 if within free tier limits).

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
2. Complete identity verification (credit card required, not charged for free tier)
3. In AWS Console → **IAM** → create a user with **AdministratorAccess** (or EC2/VPC-only for least privilege)
4. Create an Access Key for that user

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

aws:
  region: "us-east-1"
  instanceType: "t2.micro"   # free tier eligible
  instanceName: "sovereign-1"
  # amiId: ""                 # leave empty to auto-detect Ubuntu 22.04 LTS
```

### 3. Run bootstrap

```bash
./bootstrap/bootstrap.sh
```

This will:
1. Auto-detect the latest Ubuntu 22.04 LTS AMI in your region
2. Import your SSH public key to AWS
3. Create a security group allowing SSH (22), HTTP (80), HTTPS (443), and K3s API (6443)
4. Launch a t2.micro EC2 instance
5. Install K3s
6. Fetch and save kubeconfig to `~/.kube/sovereign-aws.yaml`

### 4. Configure DNS

After bootstrap, add the following records in Cloudflare (or your DNS provider):

```
Type: A   Name: *.your-domain.com   Value: <server-ip>   Proxy: DNS only
Type: A   Name: your-domain.com     Value: <server-ip>   Proxy: DNS only
```

**Important:** AWS assigns a new public IP each time the instance restarts unless you
attach an **Elastic IP** (free while the instance is running, $0.005/hr when stopped).
To avoid DNS changes on restart:

```bash
# Allocate an Elastic IP
EIP_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)

# Associate with your instance
aws ec2 associate-address \
  --instance-id <instance-id> \
  --allocation-id $EIP_ID
```

### 5. Verify the cluster

```bash
export KUBECONFIG=~/.kube/sovereign-aws.yaml
kubectl get nodes
# NAME         STATUS   ROLES                  AGE   VERSION
# ip-x-x-x-x   Ready    control-plane,master   1m    v1.29.4+k3s1

./bootstrap/verify.sh
```

## Staying Within Free Tier

- Use `t2.micro` instance type (1 vCPU, 1 GB RAM)
- Keep EBS volume under 30 GB (free tier limit)
- Stop the instance when not in use (but see Elastic IP note above)
- Monitor usage at AWS Billing → Free Tier Usage

## Scaling Up

To upgrade to a larger instance:

```bash
aws ec2 stop-instances --instance-ids <instance-id>
aws ec2 modify-instance-attribute --instance-id <instance-id> --instance-type t3.small
aws ec2 start-instances --instance-ids <instance-id>
```

## Cleanup

To avoid unexpected charges, terminate the instance and release resources when done:

```bash
aws ec2 terminate-instances --instance-ids <instance-id>
aws ec2 release-address --allocation-id <eip-allocation-id>
aws ec2 delete-security-group --group-name sovereign-k3s-sg
```

## Troubleshooting

**Permission denied (publickey):** Ubuntu 22.04 AMIs use `ubuntu` user, not `root`.
The bootstrap script automatically uses `ubuntu@<ip>`.

**AMI not found:** The auto-detection queries Canonical's official AMI catalogue.
You can specify a manual AMI ID in `config.yaml` under `aws.amiId`.

**Security group already exists:** The script is idempotent — it reuses existing resources.

**Instance takes a long time to be SSH-able:** AWS instances typically take 60–90 seconds
to boot. The script retries SSH every 10 seconds for up to 5 minutes.
