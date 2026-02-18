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

State is stored remotely in S3 (`mikey-com-terraformstate` bucket) with DynamoDB locking.

## Deployment Order

Infrastructure must be deployed sequentially due to dependencies:

1. **VPC** (`VPC/dev/`) - Network foundation
2. **OpenVPN** (`openvpn/terraform/`) - VPN access (required for private subnet access)
   - After apply: set DNS in **Configuration → VPN Settings** (Admin UI): Primary = AWS VPC DNS `10.8.0.2`, Secondary = `8.8.8.8`; enable "Have clients use specific DNS servers". See `openvpn/README.md` § Configure DNS.
3. **EC2** (`RKE-cluster/dev-cluster/ec2/`) - Kubernetes node instances
4. **RKE** (`RKE-cluster/dev-cluster/RKE/`) - Kubernetes cluster (requires VPN connection)
5. **Ingress** (`modules/ingress/`) - Traefik + External-DNS + Cert-Manager

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
