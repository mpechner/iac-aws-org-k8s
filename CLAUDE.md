# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform Infrastructure as Code (IaC) for a complete AWS environment including VPC, RKE2 Kubernetes cluster, VPN access, and ingress controller stack.

## Common Commands

All infrastructure is managed via standard Terraform workflow:

```bash
cd <component-directory>
terraform init
terraform plan
terraform apply
terraform destroy
```

State is stored remotely in S3 with DynamoDB locking. **The backend block cannot use variables;** each component has `bucket`, `region`, and `dynamodb_table` hardcoded. For a new environment, these must be updated in each file that contains a backend block. See **README.md § Terraform state backend (required setup)** for the full list of files to update: `buckets/dev-account/terraform.tf`, `deployments/rke-apps/1-infrastructure/terraform.tf`, `deployments/rke-apps/2-applications/terraform.tf`, `deployments/eks-apps/1-infrastructure/terraform.tf`, `deployments/eks-apps/2-applications/terraform.tf`, `openvpn/terraform/terraform.tf`, `Organization/providers.tf`, `RKE-cluster/dev-cluster/ec2/terraform.tf`, `RKE-cluster/dev-cluster/RKE/terraform.tf`, `EKS-cluster/eks-cluster/1-iam/providers.tf`, `EKS-cluster/eks-cluster/2-cluster/providers.tf`, `EKS-cluster/eks-cluster/3-karpenter/providers.tf`, `route53/delegate/main.tf`, `route53/dns-security/terraform.tf`, `s3backing/backend.tf`, `TF_org-user/providers.tf`, `VPC/dev/terraform.tf`.

## Deployment Order

Two cluster stacks share common VPC/VPN infrastructure. Deploy only one cluster at a time (vCPU quota constraint).

### Common (always deployed)

1. **VPC** (`VPC/dev/`) - Network foundation
2. **OpenVPN** (`openvpn/terraform/`) - VPN access (required for private subnet access)
   - After apply: set DNS in **Configuration → VPN Settings** (Admin UI): Primary = AWS VPC DNS `10.8.0.2`, Secondary = `8.8.8.8`; enable "Have clients use specific DNS servers". See `openvpn/README.md` § Configure DNS.

### RKE2 cluster (deploy OR EKS, not both)

3. **EC2** (`RKE-cluster/dev-cluster/ec2/`) - Kubernetes node instances
4. **RKE** (`RKE-cluster/dev-cluster/RKE/`) - Kubernetes cluster (requires VPN connection)
5. **Apps** (`deployments/rke-apps/`) - Traefik + External-DNS + Cert-Manager

### EKS cluster (deploy OR RKE2, not both)

3. **IAM** (`EKS-cluster/eks-cluster/1-iam/`) - Cluster and node roles
4. **Cluster** (`EKS-cluster/eks-cluster/2-cluster/`) - EKS control plane + managed node group
5. **Karpenter** (`EKS-cluster/eks-cluster/3-karpenter/`) - Node autoprovisioner
6. **Apps** (`deployments/eks-apps/`) - Ingress stack + applications

## Architecture

### Network Layout (us-west-2)

- **VPC CIDR**: 10.8.0.0/16
- **Public subnets**: 10.8.0.0/24, 10.8.64.0/24, 10.8.128.0/24
- **Private subnets**: 10.8.16.0/20, 10.8.80.0/20, 10.8.144.0/20
- **RKE subnets**: 10.8.192.0/20, 10.8.208.0/20, 10.8.224.0/20
- **DB subnets**: 10.8.32.0/26, 10.8.96.0/26, 10.8.160.0/26

### Component Structure

| Directory | Purpose |
|-----------|---------|
| `Organization/` | AWS Organization and account management, SCPs |
| `TF_org-user/` | Terraform execution roles |
| `VPC/` | VPC, subnets, NAT gateways |
| `RKE-cluster/` | EC2 instances and RKE2 Kubernetes cluster |
| `EKS-cluster/eks-cluster/` | EKS cluster (IAM, control plane, Karpenter) — runs in dev account |
| `deployments/rke-apps/` | App deployments for RKE2 cluster |
| `deployments/eks-apps/` | App deployments for EKS cluster |
| `openvpn/` | OpenVPN Access Server deployment |
| `vpn/` | Alternative AWS Client VPN |
| `route53/` | DNS zones and delegation |
| `modules/ingress/` | Kubernetes ingress stack (Traefik, External-DNS, Cert-Manager) |

### Kubernetes Access

EC2 instances are in private subnets - VPN connection required. After RKE deployment:

```bash
scp -i ~/.ssh/rke-key ubuntu@<server-ip>:/etc/rancher/rke2/rke2.yaml ~/.kube/dev-rke2.yaml
sed -i '' 's|server: https://127.0.0.1:6443|server: https://<server-ip>:6443|' ~/.kube/dev-rke2.yaml
```

### Ingress Stack

The `modules/ingress/` module deploys three integrated components:
- **Traefik**: Ingress controller (v24.0.0)
- **External-DNS**: Automatic Route53 DNS record management (v1.15.0)
- **Cert-Manager**: Let's Encrypt TLS certificates (v1.15.3)

Nodes require IAM permissions for Route53 access.

## Key Configuration

- **Primary Region**: us-west-2
- **DR Region**: us-east-2
- **Kubernetes Service CIDR**: 10.43.0.0/16
- **Cluster DNS**: 10.43.0.10
- **Network Plugin**: Flannel

## Command Scope Rules (Critical)

When I (Claude) provide a shell command like `git add`, `git commit`, `terraform apply`, etc.:

- **"Run X now"** = Execute immediately on the current state
- **"Then do Y"** = Wait for explicit confirmation before proceeding
- **No explicit timing** = Ask "Should I run this now or are you saving it for later?"

**Git commands specifically apply only to the current state:**
- "git add all untracked files" = Add files that are untracked **at that moment**
- "commit these changes" = Commit what is currently staged
- Do **not** apply these commands to work created **after** the command was issued

When the user says "git add X" or similar, I must clarify: "Should I run this now on current files, or wait for your go-ahead?"

I should never assume a command applies to future work unless explicitly told "and also add any new files I create."

## Error Diagnosis and Prompt Feedback

### On errors
- Always diagnose the root cause before fixing. State explicitly whether the cause was: (1) my mistake, (2) an ambiguous prompt, (3) a false assumption in the prompt, or (4) both. Be specific about which.
- Never open error responses with apologies. Lead with the diagnosis.

### On underspecified prompts
- When a prompt was underspecified or misleading, say explicitly what was missing or ambiguous — even when I can still produce a correct answer.
- After any significant misunderstanding, show what the ideal prompt would have looked like to get the right answer immediately.

### Honest feedback over politeness
- The user is trying to improve prompting precision. When something goes wrong, prioritize honest diagnosis over politeness.
- Tell the user what they got wrong, not just what I got wrong. Do not protect their ego at the expense of useful feedback.
