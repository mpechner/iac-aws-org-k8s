# Stage 2: Applications

This stage deploys application-level resources that depend on CRDs installed in Stage 1.

## Prerequisites

**You MUST deploy Stage 1 first!**

Stage 2 requires these CRDs to exist:
- `cert-manager.io/v1/ClusterIssuer`
- `cert-manager.io/v1/Issuer`
- `cert-manager.io/v1/Certificate`
- `traefik.io/v1alpha1/IngressRoute`
- `traefik.io/v1alpha1/Middleware`
- `traefik.io/v1alpha1/ServersTransport`

## What Gets Deployed

### ClusterIssuer
- Let's Encrypt configuration (staging or prod)
- DNS-01 challenge via Route53
- Cluster-wide certificate issuer

### Traefik Dashboard
- IngressRoute for Traefik dashboard
- Basic auth middleware (requires `traefik-auth-secret`)
- Internal-only access via internal NLB
- TLS certificate from Let's Encrypt

### Backend TLS Infrastructure
- Self-signed CA per namespace
- Automatic internal service certificates
- Traefik ServersTransport configuration
- Enables encrypted pod-to-pod communication

### Nginx Sample Application
- Kubernetes deployment + service
- Ingress with Let's Encrypt TLS
- Backend TLS enabled
- Public access via external NLB

### OpenVPN TLS cert (optional)
- Dedicated cert-manager ClusterIssuer scoped to the VPN hosted zone (uses node IAM role)
- Certificate for `vpn.<route53_domain>` (90d, renew from day 60)
- CronJob every 30 min publishes cert to `openvpn/<env>` in Secrets Manager (uses node IAM role)
- No static keys or credential Secrets — all access via `rke-nodes-role` scoped in `RKE-cluster/dev-cluster/ec2`
- See `openvpn-cert.tf` and `../../modules/tls-issue/publisher/README.md`

## Configuration

Edit `terraform.tfvars`:

```hcl
route53_domain   = "dev.foobar.support"

letsencrypt_environment = "staging"  # Use "staging" first, then "prod"

# OpenVPN cert (when openvpn_cert_enabled = true)
openvpn_cert_enabled            = true
openvpn_cert_hosted_zone_id     = "Z06437531SIUA7T3WCKTM"   # Route53 zone for route53_domain
openvpn_cert_letsencrypt_email  = "you@example.com"
openvpn_cert_publisher_image    = "REDACTED_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/openvpn-dev:latest"
# Secret path (openvpn/dev) and IAM user are derived automatically.
# Build the image first: ECR_ACCOUNT_ID=<dev-account-id> make -C scripts
```

## Deployment

```bash
terraform init
terraform apply
```

## Deploying the OpenVPN TLS cert pipeline

This is an optional sub-component. Follow these steps in order.

### Prerequisites

### Step 1 — Set variables in `terraform.tfvars`

These values are already set for dev:

```hcl
route53_domain                 = "dev.foobar.support"
letsencrypt_environment        = "prod"
openvpn_cert_enabled           = true
openvpn_cert_hosted_zone_id    = "Z06437531SIUA7T3WCKTM"
openvpn_cert_letsencrypt_email = "mikey@mikey.com"
openvpn_cert_publisher_image   = "REDACTED_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/openvpn-dev:latest"
```

If the image has not been built yet, leave `openvpn_cert_publisher_image` empty — the CronJob is skipped until it is set.

### Step 2 — Apply to create namespace, ClusterIssuer, and Certificate

```bash
terraform apply
```

Terraform creates: `openvpn-certs` namespace, dedicated ClusterIssuer (uses node role for Route53), Certificate, and RBAC. AWS credentials come from the node role — no Secrets are created here.

The CronJob is skipped until `openvpn_cert_publisher_image` is set.

Wait for the certificate to become `Ready` (DNS-01 validation takes 1–2 minutes):

```bash
kubectl get certificate -n openvpn-certs -w
# openvpn-vpn-tls   True   ...
```

### Step 3 — Build and push the publisher image

```bash
# From this directory (deployments/rke-apps/2-applications)
ECR_ACCOUNT_ID=<dev-account-id> make -C scripts
```

The script logs in to ECR, builds for `linux/amd64`, pushes, and prints the image URI.
Edit `AWS_PROFILE` at the top of the script if you use a named AWS profile.

### Step 4 — Enable the CronJob

Add the printed URI to `terraform.tfvars`:

```hcl
openvpn_cert_publisher_image = "REDACTED_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/openvpn-dev:latest"
```

Apply again:

```bash
terraform apply
```

### Step 5 — Verify

```bash
# Certificate is Ready
kubectl get certificate -n openvpn-certs

# CronJob exists
kubectl get cronjob -n openvpn-certs

# Trigger a manual run to confirm publishing works
kubectl create job --from=cronjob/openvpn-publish-cert-to-secretsmanager manual-test -n openvpn-certs
kubectl logs -n openvpn-certs -l job-name=manual-test --follow

# Confirm the secret exists in Secrets Manager
aws secretsmanager get-secret-value --secret-id openvpn/dev --query SecretString --output text | jq .fqdn
```

## Verification

```bash
# Check certificates
kubectl get certificates -A
kubectl get clusterissuers

# Verify ingresses
kubectl get ingress -A

# Check nginx sample
kubectl get pods -n nginx-sample
kubectl get svc -n nginx-sample

# Test access
curl https://nginx.dev.foobar.support
```

## Accessing Services

### Nginx Sample (Public)
- URL: https://nginx.dev.foobar.support
- Access: Internet (via external NLB)
- Certificate: Let's Encrypt (auto-renewed)

### Traefik Dashboard (Public)
- URL: https://traefik.dev.foobar.support/dashboard or https://traefik.dev.foobar.support/api
- Same public NLB as nginx; no VPN required once DNS has synced.
- Certificate: Let's Encrypt (auto-renewed)

### Rancher (Public)
- URL: https://rancher.dev.foobar.support (or your `route53_domain`)
- Same public NLB as nginx; no VPN required.

**If Traefik or Rancher don’t load:** Run 1-infrastructure apply so the public NLB gets `traefik` and `rancher` in external-dns; then wait for external-dns to update Route53 (or restart the external-dns deployment). Check certs: `kubectl get certificate -n traefik` (traefik-dashboard-tls, rancher-tls should be Ready).

## Adding New Applications

**See [ADDING-NEW-APP.md](../ADDING-NEW-APP.md)** for a step-by-step guide. In short: deploy your app, add its hostname to the public NLB in 1-infrastructure (external-dns), then in 2-applications add a Certificate and an IngressRoute in the **traefik** namespace (use `traefik.io/v1alpha1`). Do not rely on the applications module’s `ingresses` map for new apps; use the same explicit Certificate + IngressRoute pattern as nginx and rancher.

## Troubleshooting

### Certificate not issuing

```bash
# Check certificate status
kubectl describe certificate <cert-name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

### OpenVPN cert not issuing (DNS-01 challenge)

```bash
# Inspect the Certificate and its CertificateRequest
kubectl describe certificate openvpn-vpn-tls -n openvpn-certs

# Check for a failing Challenge (DNS-01)
kubectl get challenges -A
kubectl describe challenge -n openvpn-certs <challenge-name>

# Most common cause: node IAM role missing Route53 permissions.
# Verify the ClusterIssuer is Ready:
kubectl describe clusterissuer letsencrypt-vpn-prod
```

### Publisher CronJob not updating Secrets Manager

```bash
# Check recent job logs
kubectl get jobs -n openvpn-certs
kubectl logs -n openvpn-certs -l job-name=<job-name>

# Common causes:
#  - IAM policy not applied or wrong secret ARN (verify rke-nodes-role has Secrets Manager permissions)
#  - openvpn_cert_publisher_image not set (CronJob won't be created)
#  - ECR image does not exist (run `ECR_ACCOUNT_ID=<dev-account-id> make -C scripts` to build and push)
```

### Ingress not working

```bash
# Check Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik

# Verify DNS records
dig nginx.dev.foobar.support
```

### Backend TLS errors

```bash
# Check if CA certificates exist
kubectl get secrets -n <namespace> | grep backend-ca

# Verify backend certificates
kubectl get certificates -n <namespace>
```

## Destroy

**Before running `terraform destroy`**, delete the Traefik NLBs so destroy does not hang (same script as 1-infrastructure; NLBs are created by 1-infra but 2-app destroy checks for them first):

```bash
# From 2-applications (use your terraform-execute role ARN for the cluster account)
AWS_ASSUME_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/terraform-execute" bash ../../../scripts/delete-traefik-nlbs.sh
# Or: bash ../../../scripts/delete-traefik-nlbs.sh arn:aws:iam::ACCOUNT_ID:role/terraform-execute
```

If you skip the script, **terraform destroy will detect existing Traefik NLBs and fail** with a copy-pastable command; run it, then run `terraform destroy` again. See `../1-infrastructure/README.md` and `scripts/README.md` for details.

## Important Notes

- Let's Encrypt staging has high rate limits (use for testing)
- Let's Encrypt prod has strict rate limits (use after testing passes)
- Backend TLS is automatically configured per namespace
- external-dns automatically creates Route53 records for all ingresses
