# EKS Cluster Runbook

EKS cluster in the **dev AWS account** (AWS vCPU quota unavailable in prod account). Uses the shared dev VPC and OpenVPN.

**Pre-requisite:** Complete `docs/runbook-common.md` (VPC, OpenVPN, ECR) and connect to the dev VPN before proceeding.

> Deploy either this cluster **or** the RKE2 cluster — not both simultaneously (vCPU quota).

---

## Terraform state backend

Update the `backend "s3" { }` block in each file before running `terraform init`:

| File | State key |
|------|-----------|
| `EKS-cluster/eks-cluster/1-iam/providers.tf` | `eks-dev/1-iam` |
| `EKS-cluster/eks-cluster/2-cluster/providers.tf` | `eks-dev/2-cluster` |
| `EKS-cluster/eks-cluster/3-karpenter/providers.tf` | `eks-dev/3-karpenter` |
| `deployments/eks-apps/1-infrastructure/terraform.tf` | `ingress_dev/1-infrastructure` |
| `deployments/eks-apps/2-applications/terraform.tf` | `ingress_dev/2-applications` |

---

## Required: terraform.tfvars files

| Component | Required values |
|-----------|----------------|
| `EKS-cluster/eks-cluster/1-iam` | `account_id` |
| `EKS-cluster/eks-cluster/2-cluster` | `account_id`, `cluster_name`, `subnet_ids`, `vpc_id` |
| `EKS-cluster/eks-cluster/3-karpenter` | `account_id`, `cluster_name` |
| `deployments/eks-apps/1-infrastructure` | `account_id`, `aws_region`, `cluster_name`, `route53_zone_id`, `letsencrypt_email` |
| `deployments/eks-apps/2-applications` | `account_id`, `aws_region`, `cluster_name`, `letsencrypt_email`, `grafana_admin_password`, `openvpn_cert_enabled`, `openvpn_cert_hosted_zone_id`, `openvpn_cert_letsencrypt_email`, `openvpn_cert_publisher_image`, `openvpn_cert_publisher_irsa_role_arn` |

> **Subnet IDs for `2-cluster`:** EKS nodes reuse the RKE subnets (`10.8.192.0/20`, `10.8.208.0/20`, `10.8.224.0/20`) since RKE2 and EKS are never deployed simultaneously. Public subnets (`10.8.0.0/24`, `10.8.64.0/24`, `10.8.128.0/24`) are used for external NLBs.

---

## Deployment

### Step 1 — IAM

```bash
cd EKS-cluster/eks-cluster/1-iam
terraform init
terraform apply
```

Creates the EKS cluster role, managed node group role, Karpenter node role, KMS key for secrets encryption, IRSA roles (karpenter, external-dns, cert-manager, traefik, keda, openvpn-cert-publisher), and the Karpenter instance profile.

---

### Step 2 — EKS Cluster + Bootstrap Nodes

Must be connected to VPN.

```bash
cd EKS-cluster/eks-cluster/2-cluster
terraform init
terraform apply
```

Creates the EKS control plane, bootstrap node group (3× t3.medium, tainted for Karpenter only), OIDC provider, and vpc-cni/ebs-csi addons with IRSA.

---

### Step 2a — Configure kubectl

After apply, configure kubectl to use the `terraform-execute` role (required — the cluster API is private and only this role has Kubernetes access):

```bash
aws eks update-kubeconfig   --region us-west-2   --name dev-eks   --alias dev-eks --assume-role-arn arn:aws:iam::<ACCOUNT_ID>:role/terraform-execute
```

To access the cluster will need credentials to the dev cluster. 
I use the temporary credentials from the AWS access portal.

To test, run k9s or kubectl
```bash  
kubectl get nodes
```

All 3 bootstrap nodes should show `Ready`. If nodes are not ready, addons will be stuck in `CREATING` — wait for nodes before proceeding.

---

### Step 3 — Karpenter

```bash
cd EKS-cluster/eks-cluster/3-karpenter
terraform init
terraform apply
```

Installs Karpenter via Helm and creates two NodePools:

- **`spot-interruptible`** — spot capacity, stateless workloads, 24h node expiry
- **`on-demand-stable`** — on-demand, no disruption Mon–Fri 07:00–19:00 UTC, stateful/critical services

After apply, coredns and kube-proxy can move off the bootstrap nodes onto Karpenter nodes.

---

### Step 4 — Platform Infrastructure

```bash
cd deployments/eks-apps/1-infrastructure
terraform init
terraform apply
```

Deploys Traefik (dual NLB: public + internal), External-DNS, Cert-Manager, AWS Load Balancer Controller, and KEDA. Wait 2–3 minutes for all components to be ready.

---

### Step 5 — Build OpenVPN Cert Publisher Image *(if using OpenVPN certs)*

If you plan to use the OpenVPN TLS Certificate Pipeline in Step 7, build and push the publisher image first. The image is shared with the RKE2 stack — use the same Makefile:

```bash
cd deployments/rke-apps/2-applications
ECR_ACCOUNT_ID=<dev-account-id> make -C scripts
```

Copy the printed image URI into `deployments/eks-apps/2-applications/terraform.tfvars`:

```hcl
openvpn_cert_publisher_image = "<dev-account-id>.dkr.ecr.us-west-2.amazonaws.com/openvpn-dev:latest"
```

---

### Step 6 — Applications

```bash
cd deployments/eks-apps/2-applications
terraform init
terraform apply
```

Deploys:

| App | Exposure | Host |
|-----|----------|------|
| Traefik dashboard | Internal NLB | `traefik.dev.foobar.support` |
| Karpenter dashboard | Internal NLB | `karpenter.dev.foobar.support` |
| KEDA dashboard | Internal NLB | `keda.dev.foobar.support` |
| nginx (sample) | External NLB | `nginx.dev.foobar.support` |
| OpenVPN TLS cert | Secrets Manager | `vpn.dev.foobar.support` *(optional)* |

All hosts use Let's Encrypt TLS. Internal hosts require VPN.

**OpenVPN TLS cert pipeline:** Uses the same `tls-issue` module as RKE2 — same ClusterIssuer, Certificate, RBAC, and CronJob publishing to `openvpn/<env>` in Secrets Manager. Difference from RKE2: credentials come from IRSA (`openvpn-cert-publisher` role created in Step 2) rather than the EC2 node role. Set in tfvars:

```hcl
openvpn_cert_enabled                 = true
openvpn_cert_hosted_zone_id          = "<route53-zone-id>"
openvpn_cert_letsencrypt_email       = "you@example.com"
openvpn_cert_publisher_irsa_role_arn = "<arn from 3-karpenter outputs>"
```

Verify after apply:

```bash
kubectl get certificate -n openvpn-certs -w
kubectl get cronjob -n openvpn-certs
```

---

## Teardown

Destroy in reverse order. **Before** running `terraform destroy` in either apps layer, delete the Traefik NLBs or destroy will hang:

```bash
AWS_ASSUME_ROLE_ARN="arn:aws:iam::364082771643:role/terraform-execute" ./scripts/delete-traefik-nlbs.sh
```

Then destroy:

```bash
cd deployments/eks-apps/2-applications && terraform destroy
cd ../1-infrastructure && terraform destroy
cd ../../EKS-cluster/eks-cluster/3-karpenter && terraform destroy
cd ../2-cluster && terraform destroy
cd ../1-iam && terraform destroy
```

If you skip the NLB cleanup, `terraform destroy` will detect existing NLBs and fail with a copy-pastable command to run the script.

**PVC cleanup is automatic.** Two destroy-time `null_resource` provisioners handle PersistentVolumeClaim cleanup so that EBS volumes are deprovisioned in an orderly way before the CSI driver goes away:

| Where | What it cleans | When it runs |
|---|---|---|
| `2-applications/grafana.tf` → `null_resource.observability_pvc_cleanup` | PVCs in `mimir`, `loki`, `grafana`, `alloy` namespaces | During `terraform destroy` on 2-applications |
| `1-infrastructure/storageclass.tf` → `null_resource.all_pvc_cleanup` | PVCs in **every** namespace cluster-wide (safety net for anything the 2-applications cleanup missed) | During `terraform destroy` on 1-infrastructure, before the `gp3` StorageClass is destroyed |

Both resources assume the `terraform-execute` role, write a temporary kubeconfig via `aws eks update-kubeconfig`, iterate namespaces, and run `kubectl delete pvc --all -n <namespace> --wait=false --ignore-not-found`. They are idempotent — if no PVCs exist the step is a no-op. The second resource also sleeps 15 seconds after issuing deletes so the EBS CSI controller can begin processing finalizers before the rest of the destroy chain proceeds.

**Why the safety net matters:** if a PVC is still present when the `aws-ebs-csi-driver` addon is destroyed in `2-cluster`, its finalizer can no longer be processed and the PV object gets stuck in `Terminating` forever. The underlying EBS volume then leaks in AWS and has to be cleaned up manually. The `1-infrastructure` cleanup runs while the CSI driver is still alive, closing that window.

If you need to bypass the automatic cleanup for any reason (e.g., debugging a stuck destroy), you can delete PVCs manually first:

```bash
for NS in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  kubectl delete pvc --all -n "$NS" --ignore-not-found --wait=false
done
```

---

## Post-Deployment Validation

```bash
# Verify nodes and capacity types
kubectl get nodes -L node.kubernetes.io/purpose,karpenter.sh/capacity-type

# Verify Karpenter is on bootstrap nodes only
kubectl get pods -n karpenter -o wide

# Verify IRSA on key service accounts
kubectl describe sa karpenter -n karpenter | grep Annotations
kubectl describe sa cert-manager -n cert-manager | grep Annotations

# Verify Traefik NLBs
kubectl get svc -n traefik

# Verify cert-manager issuers
kubectl get clusterissuer

# Verify OpenVPN cert (if enabled)
kubectl get certificate -n openvpn-certs
kubectl get cronjob -n openvpn-certs

# Test dashboard access (requires VPN)
curl -I https://traefik.dev.foobar.support
```

---

## Troubleshooting

### `helm_release.loki` times out with "context deadline exceeded" and PVC `storage-loki-0` is Pending

Symptom:

```
helm_release.loki: Still creating... [05m00s elapsed]
Error: context deadline exceeded
```

`kubectl -n loki describe pod loki-0` shows `pod has unbound immediate PersistentVolumeClaims` and `StorageClass.storage.k8s.io "gp3" not found`. Mimir and Grafana will hit the same symptom because they rely on the cluster default StorageClass.

**Cause:** The `gp3` StorageClass is not installed in the cluster. The `aws-ebs-csi-driver` EKS addon installs the CSI controller but does not create any StorageClass objects. `deployments/eks-apps/1-infrastructure/storageclass.tf` creates `gp3` and marks it as the cluster default; if that file is missing or its resource has not been applied yet, nothing will bind. The Helm charts (Mimir, Loki, Grafana) intentionally do not pin a storageClass so they pick up whatever the cluster default is — adding a new chart with persistence does not require a per-chart storage class override.

**Recovery:**

1. Apply the StorageClass:
   ```bash
   cd deployments/eks-apps/1-infrastructure && terraform apply
   ```
2. The Helm release is now in a `failed` status even though the PVC can bind — Terraform's timeout doesn't roll it back. Clean it up:
   ```bash
   helm -n loki uninstall loki
   kubectl -n loki delete pvc --all   # StatefulSet PVCs are not deleted by helm uninstall
   ```
3. Taint and re-apply:
   ```bash
   cd deployments/eks-apps/2-applications && terraform taint helm_release.loki && terraform apply
   ```

The `helm_release.loki` timeout is set to 600 seconds in `grafana.tf` to give Karpenter enough headroom to launch a node, attach an EBS volume, and pass Loki's readiness probes on a cold start.

---

## Reference: Guardrails

| Guardrail | Where configured | Step |
|-----------|-----------------|------|
| KMS encryption for EKS secrets | `1-iam/kms.tf`, `2-cluster/main.tf` | 2–3 |
| IMDS v2 (hop limit 2 nodes, 1 pods) | `2-cluster/` launch template | 3 |
| Private API endpoint only | `2-cluster/main.tf` | 3 |
| Control plane audit logging | `2-cluster/main.tf` | 3 |
| EBS volumes encrypted by default | `1-infrastructure/` StorageClass | 5 |
| No SSH on nodes (SSM only) | `2-cluster/` node group config | 3 |
| IRSA for all platform pods | `1-iam/` IRSA roles | 2 |
| Karpenter node IMDS hop limit = 1 | EC2NodeClass userData | 4 |
| VPC endpoints (no internet for ECR/SSM) | `VPC/dev/` | Shared prereq |
| Spot interruption handling | NodePool `on-demand-stable` budget | 4 |
