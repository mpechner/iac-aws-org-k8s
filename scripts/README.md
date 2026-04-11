# Operational Scripts

This directory contains operational scripts for managing the RKE2 Kubernetes cluster and infrastructure.

## Setup Scripts

### `setup-k9s.sh`
Configure kubectl access to the RKE2 cluster from your local machine.

**Usage:**
```bash
./setup-k9s.sh <server-ip>
```

**What it does:**
- Copies kubeconfig from an RKE2 server node
- Updates the server URL to the specified IP
- Renames the context to `dev-rke2`
- Merges with your existing `~/.kube/config`

**When to use:** After deploying the RKE cluster (Step 7 in main README)

**Example:**
```bash
./setup-k9s.sh 10.8.17.188
kubectl config use-context dev-rke2
kubectl get nodes
```

---

### `create-openvpn-ssh-key.sh`
Generate an OpenVPN SSH key pair and store it in AWS Secrets Manager. Run this **before** `terraform apply` in the OpenVPN directory.

**Usage:**
```bash
./create-openvpn-ssh-key.sh <dev|prod> <account_id> [--force]
```

| Environment | Secret name | Local key |
|-------------|------------|-----------|
| `dev` | `openvpn-ssh` | `~/.ssh/openvpn-ssh-keypair.pem` |
| `prod` | `openvpn-ssh-prod` | `~/.ssh/openvpn-ssh-keypair-prod.pem` |

Idempotent — if the secret already exists and contains a valid key, it fetches the existing key without overwriting. Pass `--force` to regenerate.

**Examples:**
```bash
./create-openvpn-ssh-key.sh dev <DEV_ACCOUNT_ID>
./create-openvpn-ssh-key.sh prod <PROD_ACCOUNT_ID>
./create-openvpn-ssh-key.sh prod <PROD_ACCOUNT_ID> --force
```

---

### `setup-vpn-tls.sh`
Get a Let's Encrypt certificate for the OpenVPN hostname, set the Route53 A record (`vpn.<domain>` → server IP), and store the cert in AWS Secrets Manager for use in the OpenVPN Admin UI.

**Usage:** Run from repo root after the OpenVPN server is deployed. See script for required env vars or args (domain, Route53 zone ID, server IP, email).

**When to use:** After deploying OpenVPN (see openvpn/README.md), to enable TLS and DNS for the VPN.

---

### `get-rke-ssh-key.sh`
Retrieve and save the RKE SSH private key from AWS Secrets Manager.

**Usage:**
```bash
./get-rke-ssh-key.sh [secret-name]
```

**What it does:**
- Fetches the SSH private key from AWS Secrets Manager
- Saves it to `~/.ssh/rke-key`
- Sets proper permissions (600)

**When to use:** After deploying EC2 instances (Step 5), before deploying RKE (Step 6)

**Example:**
```bash
# Default secret name (dev-rke2-ssh-keypair)
./get-rke-ssh-key.sh

# Or specify custom secret name
./get-rke-ssh-key.sh my-custom-secret
```

---

### `delete-traefik-nlbs.sh`
Delete Traefik NLBs and their target groups. **Run before `terraform destroy`** in `deployments/rke-apps/2-applications` or `deployments/rke-apps/1-infrastructure` so destroy does not hang and leave orphans. If you skip it, destroy will detect NLBs and fail with a copy-pastable command.

```bash
# From repo root (cluster account credentials or assume role)
./delete-traefik-nlbs.sh
```

If your default AWS credentials are not in the cluster account, use the terraform-execute role so the script sees the same NLBs as Terraform:

```bash
AWS_ASSUME_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/terraform-execute" ./delete-traefik-nlbs.sh
# Or: ./delete-traefik-nlbs.sh arn:aws:iam::ACCOUNT_ID:role/terraform-execute
```

Uses `us-west-2` unless you set `AWS_REGION`. Requires AWS CLI.

---

## Maintenance Scripts

### `fix-cloud-provider.sh`
Add AWS Cloud Provider configuration to existing RKE2 nodes.

**Usage:**
```bash
./fix-cloud-provider.sh
```

**What it does:**
- Adds `cloud-provider-name: "aws"` to RKE2 config on all nodes
- Restarts RKE2 services (servers one at a time, agents in parallel)
- Waits for all nodes to be Ready
- Restarts AWS Load Balancer Controller

**When to use:** 
- **One-time fix** for clusters deployed before the cloud-provider config was added
- **Not needed** for new clusters (templates are now fixed)

**Warning:** Causes brief service disruption during restart (2-3 minutes)

---

### `patch-provider-ids.sh`
Update Kubernetes node providerIDs to AWS format for Load Balancer Controller integration.

**Usage:**
```bash
./patch-provider-ids.sh
```

**What it does:**
- Queries AWS for instance ID and availability zone for each node
- Patches node objects with AWS format providerID (`aws:///us-west-2a/i-xxxxx`)
- Restarts AWS Load Balancer Controller
- Waits 90 seconds for target registration
- Shows target group health status

**When to use:**
- **One-time fix** for clusters with `rke2://` providerIDs
- **Not needed** for new clusters (cloud-provider config is now in templates)

**Prerequisites:** AWS credentials must be valid (run `aws sso login` if expired)

---

## Volume Management

### `expand-volumes/`
Tools for expanding root volumes on running RKE2 nodes without downtime.

See [expand-volumes/README.md](expand-volumes/README.md) for detailed documentation.

**Quick reference:**

#### Verify Current Sizes
```bash
cd expand-volumes
./verify-volumes.sh dev
```

Shows current EBS volume size, filesystem size, and available space for each node.

#### Expand Volumes (Bash Script)
```bash
cd expand-volumes
./expand-root-volumes.sh dev 40
```

Expands all node root volumes to 40GB using AWS CLI and SSH.

#### Expand Volumes (Ansible)
```bash
cd expand-volumes
./generate-inventory.sh dev
ansible-playbook -i inventory.ini expand-volumes.yml --extra-vars "new_size_gb=40"
```

More robust expansion using Ansible playbook.

**When to use:**
- When nodes run out of disk space (common with Rancher)
- Before deploying resource-intensive applications
- Proactively increasing capacity

**Note:** This is non-destructive and can be done on running nodes with no downtime.

---

## Script Organization

```
scripts/
├── README.md                       # This file
├── create-openvpn-ssh-key.sh       # OpenVPN SSH key → Secrets Manager (dev or prod)
├── create-rke-ssh-key.sh           # RKE SSH key → Secrets Manager
├── setup-k9s.sh                    # kubectl/k9s configuration
├── setup-vpn-tls.sh                # OpenVPN: Let's Encrypt + Route53 + Secrets Manager
├── get-rke-ssh-key.sh              # SSH key retrieval
├── get-openvpn-ssh-key.sh          # OpenVPN SSH key retrieval
├── delete-traefik-nlbs.sh          # Remove orphaned Traefik NLBs after destroy
├── fix-cloud-provider.sh           # One-time cloud provider fix
├── patch-provider-ids.sh           # One-time providerID fix
└── expand-volumes/                 # Volume management tools
    ├── README.md               # Detailed volume expansion docs
    ├── verify-volumes.sh       # Check current volume sizes
    ├── expand-root-volumes.sh  # Bash expansion script
    ├── expand-volumes.yml      # Ansible expansion playbook
    └── generate-inventory.sh   # Generate Ansible inventory
```

---

## Common Workflows

### Initial Cluster Setup
```bash
# 1. After EC2 deployment
./get-rke-ssh-key.sh

# 2. After RKE deployment
./setup-k9s.sh 10.8.17.188
```

### Expanding Disk Space
```bash
# Check current sizes
cd expand-volumes
./verify-volumes.sh dev

# Expand to 40GB
./expand-root-volumes.sh dev 40

# Verify expansion
./verify-volumes.sh dev
```

### Fixing Cloud Provider (One-time, Legacy Clusters Only)
```bash
# Only needed if cluster was deployed before templates were fixed
./fix-cloud-provider.sh
./patch-provider-ids.sh
```

---

## Prerequisites

All scripts assume:
- You're connected to the VPN
- AWS credentials are configured (`aws sso login`)
- You have the RKE SSH key (`~/.ssh/rke-key`)
- kubectl is installed and configured

## Getting Help

For detailed help on any script:
```bash
# Most scripts show usage when run without arguments
./script-name.sh --help

# Or read the comments at the top of the script
head -20 script-name.sh
```
