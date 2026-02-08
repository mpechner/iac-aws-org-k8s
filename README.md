# tf_take2
Another attempt at creating AWS infrastructure

A few years ago I created a AWS eks env in this repo https://github.com/mpechner/terraform_play

In the last 3 years working at a company that used kubernetes, what makes a reasonable environment 
has matured.

[Network Plan](VPC/Network-Plan.md)

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
cd openvpn/terraform
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
- If you change the VPN IP Network in the OpenVPN admin panel, you must also update the `cluster_cidr_blocks` in `RKE-cluster/dev-cluster/rke/main.tf`

Get the ssh key from secret openvpn-ssh and save the private key to ~/.ssh/openvpn.pem
```bash
chmod 600 ~/.ssh/openvpn.pem 
```
Set the default password
```bash
ssh -i ~/.ssh/openvpn-ssh-keypair.pem openvpnas@54.214.242.159
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

## Step 5: Bring up the EC2 instances
```bash
cd RKE-CLUSTER/dev-cluster/ec2
terraform apply
```
Copy the secret rke-ssh private key to ~/.ssh/rke-key and set perm 0600

**Wait for EC2 Status Checks:**
Terraform will automatically wait for all EC2 instances to pass their system and instance status checks before completing. This typically takes 2-3 minutes per instance.

## Step 6: Bring up RKE server/agents
Make sure the ec2 nodes are fully up.
You must be connected to the VPN now.
```bash
cd RKE-CLUSTER/dev-cluster/rke
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

## Step 7: Configure kubectl Access

Before deploying applications, you need to configure kubectl access to the RKE cluster.

**Important:** Make sure you're connected to the VPN before running this step.

Run the setup script with **any one** of your RKE server internal IP addresses (from Step 6 output):
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

## Step 8: Deploy Ingress and Applications

Now deploy the ingress stack (Traefik, External-DNS, Cert-Manager) and applications to the Kubernetes cluster.

First, update `terraform.tfvars` with your configuration:
```bash
cd deployments/dev-cluster
# Edit terraform.tfvars with your VPC ID, Route53 zone ID, domain, and Let's Encrypt email
```

Then deploy:
```bash
terraform init
terraform apply
```

This deploys:
- **Traefik ingress controller** with dual load balancers (public + internal)
- **External-DNS** (automatic DNS records in Route53)
- **Cert-Manager** (automatic TLS certificates from Let's Encrypt)
- **Sample nginx site** at `https://nginx.dev.foobar.support` (public)
- **Traefik dashboard** at `https://traefik.dev.foobar.support` (internal, VPN required)

**Note:** The nginx site is publicly accessible. The Traefik dashboard requires VPN connection.

You can monitor the deployment with k9s:
```bash
k9s
```