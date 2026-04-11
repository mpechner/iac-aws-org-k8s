# Common Infrastructure Runbook

Shared foundation for both clusters. Deploy this once — both the RKE2 cluster (`docs/runbook-rke2.md`) and the EKS cluster (`docs/runbook-eks.md`) depend on it.

---

## Terraform state backend (required setup)

**You must set the state bucket, region, and DynamoDB table for your environment.** Terraform does not allow variables in `backend` blocks, so each component has these values hardcoded. Before running `terraform init` / `apply` in any component, update the `backend "s3" { ... }` block in that component's file.

**Common infrastructure files:**

| File | Purpose |
|------|---------|
| `buckets/dev-account/terraform.tf` | Buckets (logging, etcd backups) |
| `ecr/dev/terraform.tf` | ECR repositories |
| `openvpn/devvpn/terraform.tf` | OpenVPN server |
| `Organization/providers.tf` | AWS Organization |
| `route53/delegate/main.tf` | Route53 delegation |
| `route53/dns-security/terraform.tf` | Route53 DNS security |
| `s3backing/backend.tf` | S3 state backing |
| `TF_org-user/providers.tf` | Terraform execution roles |
| `VPC/dev/terraform.tf` | VPC infrastructure |

**RKE2-specific files:** see `docs/runbook-rke2.md`

**EKS-specific files:** see `docs/runbook-eks.md`

**To find every file that needs to be modified:** search the repo for `mikey-com-terraformstate`. That includes the backend blocks above and variable defaults (e.g. openvpn and RKE remote-state bucket variables).

---

## New Account Pre-requisites

- [ ] **EC2 vCPU quota increased** — new accounts default to 1 vCPU. Go to **Service Quotas → EC2 → Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances** and request at least 4 vCPUs before deploying any EC2 instances.
- [ ] **OpenVPN Marketplace subscription** — subscribe to **OpenVPN Access Server Community Image** in the AWS Marketplace while logged into this account before running `terraform apply` in `openvpn/devvpn`.

---

## Required: terraform.tfvars files

Account-specific values are **not hardcoded** in source. Each component requires a `terraform.tfvars` file (gitignored). Each directory has a `terraform.tfvars.example` as a starting point.

**Common components:**

| Component | File | Required values |
|-----------|------|----------------|
| `Organization` | `terraform.tfvars` | `management_account_id` |
| `TF_org-user` | `terraform.tfvars` | `mgmt_account_id`, `mgmt_org_account_id`, `dev_account_id`, `network_account_id`, `prod_account_id` |
| `buckets/dev-account` | `terraform.tfvars` | `account_id`, `aws_assume_role_arn` |
| `ecr/dev` | `terraform.tfvars` | `account_id`, `repository_names` |
| `openvpn/devvpn` | `terraform.tfvars` | `account_id` |
| `route53/delegate` | `terraform.tfvars` | `aws_account_id`, `network_account_id` |
| `route53/dns-security` | `terraform.tfvars` | `aws_account_id`, `network_account_id` |
| `VPC/dev` | `terraform.tfvars` | `account_id` |

---

## Bootstrap

### Step 1: Organization Setup

Set up the AWS Organization structure, accounts, and roles.

> **Known architectural deviation:** In this repo, the org management account is the same account as the operator IAM user. AWS best practice is a dedicated management account (no IAM users, no workloads). This cannot be changed after org creation. See [ARCH-001 in SECURITY-REVIEW.md](../SECURITY-REVIEW.md) for the full assessment.
>
> **Bootstrap depends on your setup.** See [Organization/README.md](../Organization/README.md) for two scenarios:
> - **Scenario A** (this repo): IAM user lives in the management account — bootstrap uses direct credentials
> - **Scenario B** (best practice): Dedicated management account — bootstrap uses root/break-glass credentials, then deletes them

**Short version (Scenario A — this repo's setup):**

```bash
cd Organization
cp providers.tf providers.tf.with-assume
cp providers.tf.bootstrap.example providers.tf
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set management_account_id
terraform init -reconfigure
terraform apply  # creates org, OUs, member accounts
cd ..
```

**Then create `terraform-execute` in all accounts:**

```bash
cd TF_org-user
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set all account IDs (AWS Console → Organizations → AWS accounts)
terraform init
terraform apply
cd ..
```

**Then switch Organization to the normal provider:**

```bash
cd Organization
mv providers.tf.with-assume providers.tf
terraform init -reconfigure
terraform apply
cd ..
```

**Subsequent runs** (bootstrap complete):

```bash
cd Organization
terraform init
terraform apply
cd ..
```

---

### Step 2: Create SSH Key Secrets (REQUIRED)

After the Organization is set up, create the SSH key secrets. These persist across destroy/rebuild cycles and are **not** managed by Terraform (they survive `terraform destroy`).

**Create OpenVPN SSH key pair** (creates secret `openvpn-ssh` in Secrets Manager and saves `~/.ssh/openvpn-ssh-keypair.pem`):
```bash
./scripts/create-openvpn-ssh-key.sh dev <DEV_ACCOUNT_ID>
```

**Create RKE SSH key pair** (creates secret `rke-ssh` in Secrets Manager and saves `~/.ssh/rke-key`):
```bash
./scripts/create-rke-ssh-key.sh
```

Both scripts are idempotent — if the secrets already exist, they fetch the existing keys without overwriting. Pass `--force` to regenerate if needed.

---

### Step 3: S3 Buckets

```bash
cd buckets/dev-account
terraform init
terraform apply
cd ../..
```

Creates:
- `mikey-s3-servicelogging-dev-us-west-2` — S3 access logs bucket
- `mikey-dev-rke-etcd-backups` — RKE etcd backups bucket

---

### Step 4: VPC Infrastructure

```bash
cd VPC/dev
terraform init
terraform apply
cd ../..
```

---

### Step 5: OpenVPN

```bash
cd openvpn/devvpn
terraform init
terraform apply
```

The output provides the server IP and admin URL:
```
vpn_connection_info = {
  "admin_url" = "https://54.214.242.159:943/admin"
  "client_url" = "https://54.214.242.159:943/"
  "default_user" = "openvpn"
  "server_ip" = "54.214.242.159"
}
```

**First, update the OS and reboot (before setting password):**
```bash
ssh -i ~/.ssh/openvpn-ssh-keypair.pem openvpnas@<SERVER_IP>
sudo apt update && sudo apt upgrade -y && sudo reboot
```

After reboot, set the password:
```bash
ssh -i ~/.ssh/openvpn-ssh-keypair.pem openvpnas@<SERVER_IP>
cd /usr/local/openvpn_as/scripts/
sudo ./sacli --user openvpn --new_pass APASSWORD SetLocalPassword
```

Sign in and agree to the terms. Create a non-admin user at `https://<SERVER_IP>:943/admin/user_permissions`, then download the user profile from `https://<SERVER_IP>:943/`.

**Configure DNS via sacli** (SSH to the OpenVPN server, adjust `HOSTNAME` and `DNS_ZONE`):

```bash
cd /usr/local/openvpn_as/scripts
sudo mkdir -p out && sudo chown openvpnas:openvpnas out
sudo chmod 755 out


HOSTNAME="vpn.dev.foobar.support"
sudo ./sacli --key "host.name" --value "$HOSTNAME" ConfigPut

# "custom" = use explicit DNS servers below (not auto-detected)
sudo ./sacli --key "vpn.client.routing.reroute_dns" --value "custom" ConfigPut
sudo ./sacli --key "dnsproxy.mode" --value "always" ConfigPut

DNS_PRIMARY="10.8.0.2"
DNS_SECONDARY="8.8.8.8"
DNS_ZONE="foobar.support"
sudo ./sacli --key "vpn.server.dhcp_option.dns.0" --value "$DNS_PRIMARY" ConfigPut
sudo ./sacli --key "vpn.server.dhcp_option.dns.1" --value "$DNS_SECONDARY" ConfigPut
sudo ./sacli --key "vpn.server.dhcp_option.adapter_domain_suffix" --value "$DNS_ZONE" ConfigPut

sudo ./sacli start
```

See `openvpn/README.md` for more detail.

> **VPN client subnet:** `172.27.224.0/20`. If you change this in the OpenVPN admin panel, update `cluster_cidr_blocks` in `RKE-cluster/dev-cluster/RKE/main.tf` to match.

---

### Step 6: ECR Repositories

```bash
cd ecr/dev
terraform init
terraform apply
cd ../..
```

Creates ECR repos with org-wide read, dev write, 60-day image expiry, and KMS encryption. Use the output `repository_urls` when building and pushing images.

---

## Teardown of Common Infrastructure

Destroy common infrastructure **only after** destroying both clusters completely.

**SSH key secrets are not managed by Terraform** and survive `terraform destroy`. Delete manually when fully decommissioning:

```bash
AWS_ACCOUNT_ID=$(grep -E '^\s*account_id\s*=' openvpn/devvpn/terraform.tfvars | head -1 | sed 's/.*=\s*"\([^"]*\)".*/\1/')

TEMP_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/terraform-execute" \
  --role-session-name "cleanup-ssh-secrets" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)
export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | awk '{print $3}')

aws secretsmanager delete-secret --secret-id openvpn-ssh --force-delete-without-recovery --region us-west-2
aws secretsmanager delete-secret --secret-id rke-ssh --force-delete-without-recovery --region us-west-2
```
