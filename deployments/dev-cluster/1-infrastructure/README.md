# Stage 1: Infrastructure

This stage deploys the foundational infrastructure that installs Custom Resource Definitions (CRDs) needed by Stage 2.

## What Gets Deployed

### cert-manager
- Helm chart: `jetstack/cert-manager`
- Purpose: Certificate lifecycle management and Let's Encrypt integration
- **CRDs installed:** `Certificate`, `ClusterIssuer`, `Issuer`
- **Namespace: `cert-manager`**

### external-dns
- Helm chart: `bitnami/external-dns`
- Purpose: Automatic Route53 DNS record management for LoadBalancer services
- Configuration: AWS Route53 provider with upsert-only policy
- **Namespace: `external-dns`**

### Traefik
- Helm chart: `traefik/traefik`
- Purpose: Ingress controller for HTTP/HTTPS traffic routing
- **CRDs installed:** `IngressRoute`, `Middleware`, `ServersTransport`
- **Namespace: `traefik`**

**Load balancers:**
- **Public NLB:** Internet-facing for public applications (nginx.dev.foobar.support)
- **Internal NLB:** VPN-only access for admin tools (traefik.dev.foobar.support)

## Configuration

Edit `terraform.tfvars`:

```hcl
vpc_id = "vpc-xxxxxxxxx"

route53_zone_id  = "Z0xxxxxxxxxx"
route53_domain   = "dev.foobar.support"

letsencrypt_email       = "your-email@example.com"
letsencrypt_environment = "staging"  # Use "staging" first, then "prod"
```

### Subnet discovery and NLB annotations

We find subnets in the **same VPC as the cluster** (by `vpc_name` tag, default `"dev"`), then resolve IDs in this order: (1) passed `public_subnet_ids` / `private_subnet_ids`, (2) **subnet Name tags** (e.g. `dev-pub-us-west-2a` — must match VPC/dev), (3) role tags (`kubernetes.io/role/elb` / `internal-elb`), (4) CIDR fallback. Those IDs are written into the Traefik and traefik-internal **service annotations** so the AWS Load Balancer Controller can create the NLBs. We also tag those subnets with `kubernetes.io/cluster/<cluster_name> = shared` for controller discovery.

## Deployment

```bash
terraform init
terraform apply
```

### If Terraform wants to create Traefik but it already exists

If state is out of sync (e.g. new state backend) and the plan shows "create" for Traefik:

1. Import only the **Helm release** (the release name is already in use):
   ```bash
   terraform import 'module.traefik.helm_release.traefik' traefik/traefik
   ```
2. Run **apply**. Terraform will create `traefik-internal` if it doesn’t exist in the cluster (do not import it unless the Service is already there).
   ```bash
   terraform apply
   ```

## Verification

```bash
# Check Helm releases
helm list -A

# Verify pods are running
kubectl get pods -n cert-manager
kubectl get pods -n external-dns
kubectl get pods -n traefik

# Verify CRDs are installed
kubectl get crd | grep cert-manager.io
kubectl get crd | grep traefik.io

# Check load balancers
kubectl get svc -n traefik traefik
kubectl get svc -n traefik traefik-internal
```

## Important Notes

- This stage must complete successfully before deploying Stage 2
- CRD installation happens automatically via Helm charts
- Load balancers will provision AWS NLBs (takes 2-3 minutes)
- external-dns will start monitoring services and creating Route53 records

## Next Steps

Once verification passes, proceed to `../2-applications/`
