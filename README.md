# tf_take2
Another attempt at creating AWS infrastructure

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
| `vpc/providers.tf` | VPC (if using lowercase vpc) |
| `VPC/providers.tf` | VPC (if using uppercase VPC) |

**To find every file that needs to be modified:** search the repo for `mikey-com-terraformstate`. That includes the backend blocks above and variable defaults (e.g. openvpn and RKE remote-state bucket variables).

In each file, set `bucket`, `region`, and `dynamodb_table` inside the `backend "s3" { }` block to your state bucket and DynamoDB lock table (and update any variable defaults that reference the bucket).

# Bootstrap

## Step 1: Organization Setup
Set up the AWS Organization structure, accounts, and roles first.
```bash
cd Organization
terraform init
terraform apply
cd ..
```

## Step 2: S3 Buckets
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

## Step 3: VPC Infrastructure
```bash
cd VPC
terraform apply
cd ..
```

## Step 4: VPN
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

Get the OpenVPN SSH key (saved to ~/.ssh/openvpn-ssh-keypair.pem). From repo root, or from `openvpn/devvpn` use `../../scripts/`:
```bash
# From repo root:
./scripts/get-openvpn-ssh-key.sh
# From openvpn/devvpn:
../../scripts/get-openvpn-ssh-key.sh
# Or with a different secret name: .../get-openvpn-ssh-key.sh <secret-name>
```

Set the default password (use the server IP from terraform output):
```bash
ssh -i ~/.ssh/openvpn-ssh-keypair.pem openvpnas@<SERVER_IP>
```

```bash
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

**Hostname:** In the Admin UI go to **Configuration → Network Settings** and set the hostname to the full domain name (e.g. `vpn.dev.foobar.support`). Save and Update Running Server if prompted.

**DNS (required for internal resolution):** In the Admin UI go to **Configuration → VPN Settings**. In the DNS section:
- Enable **Have clients use specific DNS servers**
- **Primary DNS Server:** `10.8.0.2` (AWS VPC internal DNS for dev VPC)
- **Secondary DNS Server:** `8.8.8.8`
- **DNS Resolution Zones (optional):** Add the domain you use for internal services (e.g. `foobar.support`) so VPN clients resolve those hostnames via the VPC DNS (e.g. `nginx.dev.foobar.support`, `rancher.dev.foobar.support`).
- Save and Update Running Server.

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

## Step 5: Create ECR repository

Create the ECR repository (e.g. `vpncertrotate`) used for the OpenVPN cert rotation Lambda image and other container images. Configure `ecr/dev/variables.tf` or `terraform.tfvars` (copy from `terraform.tfvars.example`) with your `account_id`, `org_id`, and `repository_names`.

```bash
cd ecr/dev
terraform init
terraform apply
cd ../..
```

This creates the ECR repo(s) with org-wide read, dev (and configured) write, 60-day image expiry, and KMS encryption. Use the output `repository_urls` when building and pushing images (e.g. `openvpncert/lambda` with `make push`).

## Step 6: Bring up the EC2 instances
```bash
cd RKE-cluster/dev-cluster/ec2
terraform apply
```

**IMPORTANT - SSH Key Setup Required:**

Before proceeding to Step 7, you MUST copy the RKE SSH private key:

```bash
# From repo root (quick method - default secret name rke-ssh from RKE-cluster/dev-cluster/ec2):
./scripts/get-rke-ssh-key.sh

# From RKE-cluster/dev-cluster/ec2 (after terraform apply):
../../../scripts/get-rke-ssh-key.sh

# Or specify a different secret name:
# ./scripts/get-rke-ssh-key.sh <secret-name-from-output>
# ../../../scripts/get-rke-ssh-key.sh <secret-name-from-output>
```

**Without this SSH key, Step 7 will fail with authentication errors!**

**Wait for EC2 Status Checks:**
Terraform will automatically wait for all EC2 instances to pass their system and instance status checks before completing. This typically takes 2-3 minutes per instance.

## Step 7: Bring up RKE server/agents
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

## Step 8: Configure kubectl Access

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

## Step 9: Deploy Infrastructure Components

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

## Step 10: Deploy Applications

Now deploy applications (Rancher, Nginx sample, Traefik Dashboard).

```bash
cd ../2-applications
terraform init
terraform apply
```

This deploys:
- **Rancher** at `https://rancher.dev.foobar.support` (Kubernetes management UI). **Initial login:** username `admin`, password `admin` (change on first use).
- **Sample nginx site** at `https://nginx.dev.foobar.support`
- **Traefik dashboard** at `https://traefik.dev.foobar.support/dashboard`

**Note:** All three are on the same public NLB; no VPN required once DNS has synced. See `deployments/dev-cluster/ADDING-NEW-APP.md` to add more apps.

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