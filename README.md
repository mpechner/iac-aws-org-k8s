# tf_take2
Another attempt at creating AWS infrastructure

**⚠️ AI-Generated Code Warning:** This project was written entirely using **agenic methods** — a combination of Claude (Haiku, Sonnet, Opus) and other AI assistants (Kimi, etc.). 

**Critical Lesson:** Even when explicitly requesting security reviews and penetration testing, **basic security principles were missed** by the various agents. Security vulnerabilities including HTTP method exposure (TRACE), missing security headers, and server version disclosure were not caught during initial code generation or code review requests.

**When writing AI-generated infrastructure code:**
- [ ] **Explicit security passes are required** — AI agents do not inherently apply security best practices
- [ ] **Penetration testing is essential** — Automated testing revealed issues missed by AI "code reviews"
- [ ] **Defense in depth must be designed in** — Not automatically added by AI agents
- [ ] **Additional human/AI review cycles are necessary** — First-pass AI code requires security-focused iteration
- [ ] **Document accepted risks** — Some findings (like TRACE for internal dev tools) may be acceptable with proper documentation

See [SECURITY-REVIEW.md](SECURITY-REVIEW.md) and [penetration-test/](penetration-test/) for detailed findings and remediation.

**Note:** This repo is public. The **ECR** (`ecr/`) component is in progress and not tested.

A few years ago I created a AWS eks env in this repo https://github.com/mpechner/terraform_play

In the last 3 years working at a company that used kubernetes, what makes a reasonable environment 
has matured.

[Network Plan](VPC/Network-Plan.md)

## What this demonstrates

End-to-end **Infrastructure as Code** for a production-style AWS + Kubernetes environment: VPC, VPN, RKE2 cluster, and a full ingress stack with automatic TLS and DNS. All of it is Terraform-managed with remote state and a clear deployment order.

**Technologies:** Terraform, AWS (VPC, EC2, Route53, IAM, NLBs), Kubernetes (RKE2, Helm, CRDs), Traefik, cert-manager, external-DNS, Rancher. Security: private subnets, VPN for cluster access, Let's Encrypt production certificates.

Suitable as a reference for multi-account AWS, Kubernetes operations, and ingress/TLS patterns.

## Terraform state backend (required setup)

**You must set the state bucket, region, and DynamoDB table for your environment.** Terraform does not allow variables in `backend` blocks, so each component has these values hardcoded. Before running `terraform init` / `apply` in any component, update the `backend "s3" { ... }` block in that component’s file below.

**Files to update (each contains a backend block):**

| File | Purpose |
|------|---------|
| `buckets/dev-account/terraform.tf` | Buckets (logging, etcd backups) |
| `deployments/dev-cluster/1-infrastructure/terraform.tf` | Dev cluster infrastructure |
| `deployments/dev-cluster/2-applications/terraform.tf` | Dev cluster applications |
| `ecr/dev/terraform.tf` | ECR repositories |
| `openvpn/devvpn/terraform.tf` | OpenVPN server |
| `Organization/providers.tf` | AWS Organization |
| `RKE-cluster/dev-cluster/ec2/terraform.tf` | RKE EC2 nodes |
| `RKE-cluster/dev-cluster/RKE/terraform.tf` | RKE cluster |
| `route53/delegate/main.tf` | Route53 delegation |
| `route53/dns-security/terraform.tf` | Route53 DNS security |
| `s3backing/backend.tf` | S3 state backing |
| `TF_org-user/providers.tf` | Terraform execution roles |
| `VPC/providers.tf` | VPC infrastructure |

**To find every file that needs to be modified:** search the repo for `mikey-com-terraformstate`. That includes the backend blocks above and variable defaults (e.g. openvpn and RKE remote-state bucket variables).

In each file, set `bucket`, `region`, and `dynamodb_table` inside the `backend "s3" { }` block to your state bucket and DynamoDB lock table (and update any variable defaults that reference the bucket).

## Required: terraform.tfvars files

Account-specific values (AWS account ID, IAM role ARNs, hosted zone IDs, email, domain) are **not hardcoded** in the source. Each component requires a `terraform.tfvars` file. These files are gitignored (`*.tfvars`) and must be created locally.

Each directory has a `terraform.tfvars.example` as a starting point where available. The table below lists every required tfvars file and the values you must set:

| Component | File | Required values |
|-----------|------|----------------|
| `buckets/dev-account` | `terraform.tfvars` | `account_id`, `aws_assume_role_arn` |
| `deployments/dev-cluster/1-infrastructure` | `terraform.tfvars` | `account_id`, `aws_assume_role_arn`, `route53_zone_id`, `route53_domain`, `letsencrypt_email`, `letsencrypt_environment`, `cluster_name` |
| `deployments/dev-cluster/2-applications` | `terraform.tfvars` | `account_id`, `aws_assume_role_arn`, `route53_domain`, `letsencrypt_environment`, `openvpn_cert_enabled`, `openvpn_cert_hosted_zone_id`, `openvpn_cert_letsencrypt_email`, `openvpn_cert_publisher_image` |
| `ecr/dev` | `terraform.tfvars` | `account_id`, `repository_names` |
| `openvpn/devvpn` | `terraform.tfvars` | `account_id` |
| `RKE-cluster/dev-cluster/ec2` | `terraform.tfvars` | `aws_account_id`, `route53_hosted_zone_ids` |
| `RKE-cluster/dev-cluster/RKE` | `terraform.tfvars` | `aws_account_id` |
| `route53/delegate` | `terraform.tfvars` | `aws_account_id`, `network_account_id` |
| `route53/dns-security` | `terraform.tfvars` | `aws_account_id`, `network_account_id` |
| `vpc/dev` | `terraform.tfvars` | `account_id` |

# Bootstrap

## Step 1: Organization Setup
Set up the AWS Organization structure, accounts, and roles first.
```bash
cd Organization
terraform init
terraform apply
cd ..
```

## Step 2: Create SSH Key Secrets (REQUIRED)

After the Organization is set up, create the SSH key secrets that will be used throughout the deployment. These secrets persist across destroy/rebuild cycles and are **not** managed by Terraform (they survive `terraform destroy`).

**Create OpenVPN SSH key pair** (creates secret `openvpn-ssh` in Secrets Manager and saves `~/.ssh/openvpn-ssh-keypair.pem`):
```bash
export AWS_ACCOUNT_ID=<your-dev-account-id>
./scripts/create-openvpn-ssh-key.sh
```

**Create RKE SSH key pair** (creates secret `rke-ssh` in Secrets Manager and saves `~/.ssh/rke-key`):
```bash
export AWS_ACCOUNT_ID=<your-dev-account-id>
./scripts/create-rke-ssh-key.sh
```

Both scripts are idempotent — if the secrets already exist, they fetch the existing keys without overwriting. Pass `--force` to regenerate if needed.

## Step 3: S3 Buckets
Create required S3 buckets for logging and backups.
```bash
cd buckets/dev-account
terraform init
terraform apply
cd ../..
```

This creates:
- `mikey-s3-servicelogging-dev-us-west-2` - S3 access logs bucket
- `mikey-dev-rke-etcd-backups` - RKE etcd backups bucket

## Step 4: VPC Infrastructure

The VPC is deployed from `VPC/` (not `VPC/dev/`). This uses an **S3 backend** so the VPC state is shared and can be referenced by other components (like OpenVPN).

```bash
cd VPC
terraform init
terraform apply
cd ..
```

**Important:** The `VPC/` root only deploys the `dev` environment (defined in `VPC/main.tf`). If you need other environments (staging, prod), add more module blocks or run from those subdirectories separately.

**Why not `VPC/dev/`?** That directory uses a local state file (no backend), which means only your machine can access it. OpenVPN reads the VPC ID from S3 remote state, so you must use `VPC/` for shared infrastructure.

## Step 5: VPN

```bash
cd openvpn/devvpn
terraform init
terraform apply
```

The output will provide important information for connecting. Since the security group is using my comcast public IP feel safe with defaults. BUT WE ALL KNOW THIS IS BAD! The default password is not set.
```
vpn_connection_info = {
  "admin_url" = "https://54.214.242.159:943/admin"
  "client_url" = "https://54.214.242.159:943/"
  "default_user" = "openvpn"
  "server_ip" = "54.214.242.159"
}
```

**Important VPN Configuration:**
- The OpenVPN client subnet is configured as `172.27.224.0/20`
- This subnet is added to the RKE security groups to allow kubectl/k9s access from VPN-connected clients
- If you change the VPN IP Network in the OpenVPN admin panel, you must also update the `cluster_cidr_blocks` in `RKE-cluster/dev-cluster/RKE/main.tf`


**Important: First, update the OS and reboot (before setting password):**
```bash
ssh -i ~/.ssh/openvpn-ssh-keypair.pem openvpnas@<SERVER_IP>

sudo apt update
sudo apt upgrade -y
sudo reboot
```

After reboot, SSH back in and set the default password:
```bash
ssh -i ~/.ssh/openvpn-ssh-keypair.pem openvpnas@<SERVER_IP>
cd /usr/local/openvpn_as/scripts/
sudo ./sacli --user openvpn --new_pass APASSWORD SetLocalPassword
```
Sign in and Agree to the terms

Create your user. Even for play, do not use default admin profile
https://54.214.242.159:943/admin/user_permissions - create new user
From the commandline as root, run sacli to set the users password.

Download the users profile
https://54.214.242.159:943/
login and download the profile. User-locked or autologin. Again, since this is a lab and not production on server locked to a specific IP address, I am using the autologin profile.

**Hostname (OpenVPN 3.0.1+):** In the Admin UI go to **VPN Server** (left sidebar) → **Network Settings** tab and set the **Hostname (or IP address)** to the full domain name (e.g. `vpn.dev.foobar.support`). Interface should be "All interfaces". Click **Save** at the top right.

**DNS (required for internal resolution):** In the Admin UI go to **Access Controls** (left sidebar) → **Internet Access and DNS** tab. Configure:
- Select **Split-Tunnel**
- **Push DNS:** On
- **Select DNS Servers:** Custom
- **DNS Server:** `10.8.0.2` (AWS VPC internal DNS for dev VPC)
- Click **Add another DNS server** and add `8.8.8.8`
- **Default Domain Suffix (optional):** `foobar.support`
- **DNS Resolution Zones (optional):** `foobar.support`
- Click **Save** at the top right.

**Or use sacli (one script):** SSH to the OpenVPN server, then run from `/usr/local/openvpn_as/scripts/` (adjust `HOSTNAME` and `DNS_ZONE` for your environment):

```bash
cd /usr/local/openvpn_as/scripts

HOSTNAME="vpn.dev.foobar.support"
./sacli --key "host.name" --value "$HOSTNAME" ConfigPut

./sacli --key "vpn.client.routing.reroute_dns" --value "true" ConfigPut

DNS_ZONE="foobar.support"   # optional; set to "" to skip
echo 'push "dhcp-option DNS 10.8.0.2"'  > /tmp/dns.txt
echo 'push "dhcp-option DNS 8.8.8.8"'   >> /tmp/dns.txt
[ -n "$DNS_ZONE" ] && echo 'push "dhcp-option DOMAIN '"$DNS_ZONE"'"' >> /tmp/dns.txt
./sacli --key "vpn.server.config_text" --value_file=/tmp/dns.txt ConfigPut

./sacli start
```

See `openvpn/README.md` for more detail and notes on `vpn.server.config_text`.

## Step 6: Create ECR repository

Create the ECR repository (e.g. `vpncertrotate`) used for the OpenVPN cert rotation Lambda image and other container images. Configure `ecr/dev/variables.tf` or `terraform.tfvars` (copy from `terraform.tfvars.example`) with your `account_id`, `org_id`, and `repository_names`.

**Note on ECR Authentication:** This setup uses IAM instance profiles for node-level ECR access (see `RKE-cluster/modules/ec2/policies/ecr-pull-policy.json`). For pod-level ECR access control, see the optional [IRSA module](modules/irsa/README.md) (IAM Roles for Service Accounts).

```bash
cd ecr/dev
terraform init
terraform apply
cd ../..
```

This creates the ECR repo(s) with org-wide read, dev (and configured) write, 60-day image expiry, and KMS encryption. Use the output `repository_urls` when building and pushing images (e.g. `openvpncert/lambda` with `make push`).

## Step 7: Bring up the EC2 instances

```bash
cd RKE-cluster/dev-cluster/ec2
terraform apply
```

**Wait for EC2 Status Checks:**
Terraform will automatically wait for all EC2 instances to pass their system and instance status checks before completing. This typically takes 2-3 minutes per instance.

## Step 8: Bring up RKE server/agents
Make sure the ec2 nodes are fully up.
You must be connected to the VPN now.
```bash
cd RKE-cluster/dev-cluster/RKE
terraform apply
```

**Automated Health Checks:**
Terraform will automatically verify:
1. Deploy RKE2 on all server nodes
2. Wait for the Kubernetes API server to be ready
3. Verify CNI (Canal) pods are running
4. Deploy RKE2 on all agent nodes
5. **Verify all RKE2 services are running** (rke2-server on all servers, rke2-agent on all agents)
6. Check that nodes are joining the cluster and becoming Ready

**Priority:** The deployment will fail immediately if any RKE2 service is not running. Node readiness is checked but won't fail the deployment as services may take time to fully initialize.

This process typically takes 5-10 minutes.

## Step 9: Configure kubectl Access

Before deploying applications, you need to configure kubectl access to the RKE cluster.

**Important:** Make sure you're connected to the VPN before running this step.

Run the setup script with **any one** of your RKE server internal IP addresses (from Step 7 output):
```bash
# Use any of your 3 RKE server IPs, for example:
./scripts/setup-k9s.sh 10.8.17.181
```

This script will:
- Copy the kubeconfig from the RKE server
- Update the server URL
- Rename the context to `dev-rke2`
- Merge with your existing kubeconfig

Verify access:
```bash
kubectl config use-context dev-rke2
kubectl get nodes
```

## Step 10: Deploy Infrastructure Components

Deploy the core Kubernetes infrastructure (Traefik, External-DNS, Cert-Manager, AWS Load Balancer Controller).

```bash
cd deployments/dev-cluster/1-infrastructure
terraform init
terraform apply
```

This deploys:
- **Traefik ingress controller** with dual load balancers (public + internal)
- **External-DNS** (automatic DNS records in Route53)
- **Cert-Manager** (automatic TLS certificates from Let's Encrypt)
- **AWS Load Balancer Controller** (manages NLBs for LoadBalancer services)

Wait for all infrastructure components to be ready (2-3 minutes).

## Step 11: Build OpenVPN Cert Publisher Docker Image (REQUIRED if using OpenVPN certs)

If you plan to use the **OpenVPN TLS Certificate Pipeline** (deployed in Step 11), you MUST build and push the publisher Docker image FIRST.

The CronJob uses a custom Docker image (`openvpn-dev:latest`) that publishes certificates to AWS Secrets Manager. **Without this image, the OpenVPN cert deployment will fail.**

**Build and push the image:**
```bash
cd deployments/dev-cluster/2-applications
AWS_ACCOUNT_ID=<your-account-id> make -C scripts
```

See `deployments/dev-cluster/2-applications/README.md` § "Deploying the OpenVPN TLS cert pipeline" for full details.

---

## Step 12: Deploy Applications

Now deploy applications (Rancher, Nginx sample, Traefik Dashboard, and optionally OpenVPN cert pipeline).

```bash
cd ../2-applications
terraform init
terraform apply
```

This deploys:
- **Rancher** at `https://rancher.dev.foobar.support` (Kubernetes management UI). **Initial login:** username `admin`, password `admin` (change on first use).
- **Sample nginx site** at `https://nginx.dev.foobar.support`
- **Traefik dashboard** at `https://traefik.dev.foobar.support/dashboard`
- **OpenVPN TLS Certificate Pipeline** (optional) - Automated Let's Encrypt certificate for VPN + CronJob (requires Step 11 above)

**Note:** All three web apps are on the same public NLB; no VPN required once DNS has synced. See `deployments/dev-cluster/ADDING-NEW-APP.md` to add more apps.

You can monitor the deployment with k9s:
```bash
k9s
```

## Teardown / Destroy

Destroy in **reverse order**: 2-applications first, then 1-infrastructure.

**Before** running `terraform destroy` in either layer, delete the Traefik NLBs so destroy does not hang and leave orphans:

```bash
# From repo root (use cluster account role if your default credentials are not in that account)
AWS_ASSUME_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/terraform-execute" ./scripts/delete-traefik-nlbs.sh
# Or: ./scripts/delete-traefik-nlbs.sh arn:aws:iam::ACCOUNT_ID:role/terraform-execute
```

Then destroy:

```bash
cd deployments/dev-cluster/2-applications
terraform destroy

cd ../1-infrastructure
terraform destroy
```

If you skip the script, `terraform destroy` will detect existing Traefik NLBs and **fail with a copy-pastable command** to run the script, then you run destroy again. See `deployments/dev-cluster/1-infrastructure/README.md` and `scripts/README.md` for details.

**SSH key secrets are not managed by Terraform and are NOT deleted on `terraform destroy`.** This is intentional — the secrets survive a destroy/rebuild cycle so the same keys can be reused. To fully decommission the environment, delete them manually after all other resources are destroyed:

```bash
export AWS_ACCOUNT_ID=364082771643

# Assume terraform-execute role
TEMP_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/terraform-execute" \
  --role-session-name "cleanup-ssh-secrets" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)
export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | awk '{print $3}')

aws secretsmanager delete-secret \
  --secret-id openvpn-ssh \
  --force-delete-without-recovery \
  --region us-west-2

aws secretsmanager delete-secret \
  --secret-id rke-ssh \
  --force-delete-without-recovery \
  --region us-west-2
```

## Optional: IRSA (IAM Roles for Service Accounts)

For fine-grained pod-level IAM access (e.g., specific pods accessing specific ECR repositories), you can set up IRSA using the `modules/irsa` module:

```bash
cd modules/irsa
terraform init
terraform apply
```

See [modules/irsa/README.md](modules/irsa/README.md) for full setup instructions and RKE2 integration.

## Recent Changes

- **RKE2 Templates Fixed**: Removed `ecr-credential-provider` binary download (not available) and fixed template escaping
- **IRSA Module Added**: New `modules/irsa/` for IAM Roles for Service Accounts automation
- **OpenVPN TLS Certificate Pipeline**: Added `openvpn-cert.tf` with automated Let's Encrypt certificate issuance and CronJob to publish to AWS Secrets Manager. **⚠️ REQUIRES: Build and push `openvpn-dev:latest` Docker image to ECR BEFORE deploying (see Step 10).**