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

**AWS access:** All AWS operations use Terraform’s configured assume role (`terraform-execute` by default). No scripts or AWS profile / env vars are required.

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

## Destroy: Delete Traefik NLBs First

Terraform does **not** create the NLBs directly—the **AWS Load Balancer Controller** does when it sees the LoadBalancer Services. During destroy, the controller is removed before the Traefik Services, so NLBs can be left behind and Services can hang in **Terminating**.

**Before running `terraform destroy`**, delete the Traefik NLBs (from repo root or from this directory):

```bash
# From 1-infrastructure (use your terraform-execute role ARN)
AWS_ASSUME_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/terraform-execute" bash ../../../scripts/delete-traefik-nlbs.sh
# Or: bash ../../../scripts/delete-traefik-nlbs.sh arn:aws:iam::ACCOUNT_ID:role/terraform-execute
```

Set `AWS_REGION` if not `us-west-2`. If your default credentials are not in the cluster account, you must set `AWS_ASSUME_ROLE_ARN` or pass the role ARN as the first argument so the script sees the same NLBs as Terraform.

If you skip the script, **terraform destroy will detect existing Traefik NLBs and fail** with a copy-pastable command; run that command, then run `terraform destroy` again.

**If destroy already hung or left orphan NLBs:** Run the script above. If Services are stuck in Terminating, clear finalizers and retry:
```bash
kubectl patch svc -n traefik traefik-internal -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl patch svc -n traefik traefik -p '{"metadata":{"finalizers":null}}' --type=merge
```
Then run `terraform destroy` again.

## Troubleshooting: NLB target groups have no healthy targets

If the NLBs are created but target groups show no healthy targets:

1. **No registered targets**  
   We use **instance** target type. RKE2 sets node `providerID` to `rke2://nodename`, which the AWS LB controller does not use to register EC2 instances. **Provider-ID patching is done by Terraform** (same assume role as the rest of the stack—no scripts, no AWS profile or env vars). With `patch_node_provider_ids = true` (default), `terraform apply` will:
   - Resolve each node’s InternalIP to an EC2 instance ID using the Terraform AWS provider (terraform-exec role)
   - Patch each node’s `providerID` to `aws:///az/instance-id` via `kubectl` (kubeconfig only)
   - Restart the AWS Load Balancer Controller so it registers instance targets  
   After apply, target groups should show healthy instance targets within a few minutes. To disable patching (e.g. you manage providerIDs elsewhere), set `patch_node_provider_ids = false` in tfvars or CLI.

2. **Confirm Traefik pods and Service**
   ```bash
   kubectl get pods -n traefik
   kubectl get svc -n traefik
   kubectl get endpoints -n traefik
   ```
   Pods should be Ready; the Traefik Service should have NodePort(s) and endpoints.

3. **Health checks**  
   Both Traefik services use TCP health checks on the traffic port (no HTTP path). If you changed annotations, ensure `aws-load-balancer-healthcheck-protocol` is `TCP` and `aws-load-balancer-healthcheck-port` is `traffic-port`.

4. **Node security group (RKE EC2)**  
   NLB health checks come from the VPC. In `RKE-cluster/dev-cluster/ec2` (or your EC2 module), the node security group must allow:
   - **Instance targets:** NodePort range (e.g. 30000–32767) from the VPC CIDR.
   - **IP targets:** Ports 80/443 from the VPC (or 0.0.0.0/0 if you already allow public NLB traffic).

5. **Manual check (from a node or VPN)**  
   Get the Traefik Service NodePort: `kubectl get svc -n traefik traefik -o jsonpath='{.spec.ports[0].nodePort}'`. Then from a machine that can reach the nodes (e.g. VPN): `curl -v <node-internal-ip>:<nodePort>` — connection should succeed (TCP is enough for health).

6. **AWS Console**  
   In EC2 → Target Groups → select the NLB’s target group → Targets: check “Status” and “Status reason” for each target.
</think><｜tool▁call▁begin｜>
TodoWrite

## Next Steps

Once verification passes, proceed to `../2-applications/`
