# RKE2 Cluster Runbook

RKE2 Kubernetes cluster on EC2 in the dev account.

**Pre-requisite:** Complete `docs/runbook-common.md` (VPC, OpenVPN, ECR) and connect to the dev VPN before proceeding.

> Deploy either this cluster **or** the EKS cluster — not both simultaneously (vCPU quota).

---

## Terraform state backend

Update the `backend "s3" { }` block in each file before running `terraform init`:

| File | State key |
|------|-----------|
| `RKE-cluster/dev-cluster/ec2/terraform.tf` | `rke-ec2` |
| `RKE-cluster/dev-cluster/RKE/terraform.tf` | `rke-cluster` |
| `deployments/rke-apps/1-infrastructure/terraform.tf` | `ingress_dev/1-infrastructure` |
| `deployments/rke-apps/2-applications/terraform.tf` | `ingress_dev/2-applications` |

---

## Required: terraform.tfvars files

| Component | Required values |
|-----------|----------------|
| `RKE-cluster/dev-cluster/ec2` | `aws_account_id`, `route53_hosted_zone_ids` |
| `RKE-cluster/dev-cluster/RKE` | `aws_account_id` |
| `deployments/rke-apps/1-infrastructure` | `account_id`, `aws_assume_role_arn`, `route53_zone_id`, `route53_domain`, `letsencrypt_email`, `letsencrypt_environment`, `cluster_name` |
| `deployments/rke-apps/2-applications` | `account_id`, `aws_assume_role_arn`, `route53_domain`, `letsencrypt_environment`, `openvpn_cert_enabled`, `openvpn_cert_hosted_zone_id`, `openvpn_cert_letsencrypt_email`, `openvpn_cert_publisher_image` |

---

## Deployment

### Step 1: EC2 Instances

```bash
cd RKE-cluster/dev-cluster/ec2
terraform apply
```

Terraform waits for all EC2 instances to pass status checks (typically 2–3 minutes per instance).

---

### Step 2: RKE2 Cluster

Must be connected to VPN. Wait for EC2 instances to be fully up.

```bash
cd RKE-cluster/dev-cluster/RKE
terraform apply
```

Terraform automatically:
1. Deploys RKE2 on all server nodes
2. Waits for the Kubernetes API to be ready
3. Verifies CNI (Canal) pods are running
4. Deploys RKE2 on all agent nodes
5. Verifies all RKE2 services are running
6. Checks nodes are joining and becoming Ready

Typically takes 5–10 minutes.

---

### Step 3: Configure kubectl

Run with any one of your RKE server internal IPs (from Step 1 output):

```bash
./scripts/setup-k9s.sh 10.8.17.181
```

This copies the kubeconfig, updates the server URL, renames the context to `dev-rke2`, and merges with your existing kubeconfig.

```bash
kubectl config use-context dev-rke2
kubectl get nodes
```

---

### Step 4: Platform Infrastructure

```bash
cd deployments/rke-apps/1-infrastructure
terraform init
terraform apply
```

Deploys Traefik (dual NLB: public + internal), External-DNS, Cert-Manager, and AWS Load Balancer Controller. Wait 2–3 minutes for all components to be ready.

---

### Step 5: Build OpenVPN Cert Publisher Image (if using OpenVPN certs)

If you plan to use the OpenVPN TLS Certificate Pipeline in Step 6, build the publisher image first:

```bash
cd deployments/rke-apps/2-applications
ECR_ACCOUNT_ID=<dev-account-id> make -C scripts
```

See `deployments/rke-apps/2-applications/README.md` § "Deploying the OpenVPN TLS cert pipeline" for details.

---

### Step 6: Applications

```bash
cd deployments/rke-apps/2-applications
terraform init
terraform apply
```

Deploys:
- **Rancher** at `https://rancher.dev.foobar.support` (initial login: `admin` / `admin`)
- **Nginx sample** at `https://nginx.dev.foobar.support`
- **Traefik dashboard** at `https://traefik.dev.foobar.support/dashboard`
- **OpenVPN TLS Certificate Pipeline** (optional — requires Step 5)

All three web apps are on the same public NLB; no VPN required once DNS has synced. See `deployments/rke-apps/ADDING-NEW-APP.md` to add more apps.

---

## Teardown

Destroy in reverse order: 2-applications first, then 1-infrastructure.

**Before** running `terraform destroy` in either layer, delete the Traefik NLBs:

```bash
AWS_ASSUME_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/terraform-execute" ./scripts/delete-traefik-nlbs.sh
```

Then destroy:

```bash
cd deployments/rke-apps/2-applications
terraform destroy

cd ../1-infrastructure
terraform destroy
```

If you skip the NLB cleanup, `terraform destroy` will detect existing NLBs and fail with a copy-pastable command to run the script. See `deployments/rke-apps/1-infrastructure/README.md` and `scripts/README.md` for details.

---

## Optional: IRSA

For fine-grained pod-level IAM access:

```bash
cd modules/irsa
terraform init
terraform apply
```

See [modules/irsa/README.md](../modules/irsa/README.md) for full setup and RKE2 integration.

---

## Recent Changes

- **RKE2 Templates Fixed**: Removed `ecr-credential-provider` binary download (not available) and fixed template escaping
- **IRSA Module Added**: New `modules/irsa/` for IAM Roles for Service Accounts automation
- **OpenVPN TLS Certificate Pipeline**: Added `openvpn-cert.tf` with automated Let's Encrypt certificate issuance and CronJob to publish to AWS Secrets Manager. **Requires: Build and push `openvpn-dev:latest` Docker image to ECR BEFORE deploying (see Step 5).**
