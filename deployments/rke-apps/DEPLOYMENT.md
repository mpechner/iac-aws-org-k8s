# Quick Start - RKE Cluster Ingress Deployment

## Two-Stage Deployment (Required)

This deployment uses a **2-stage approach** to handle Terraform's CRD validation limitations.

### Stage 1: Infrastructure (Helm Charts)

```bash
cd 1-infrastructure
terraform init
terraform apply
```

Deploys: cert-manager, external-dns, Traefik (+ CRD installation)

### Stage 2: Applications (Manifests)

```bash
cd ../2-applications
terraform init
terraform apply
```

Deploys: ClusterIssuers, IngressRoutes, backend TLS, nginx-sample

## Why Two Stages?

Terraform validates `kubernetes_manifest` resources during `terraform plan` **before** any deployment happens. This means:

- If we deploy Helm charts and manifests together, Terraform tries to validate manifests for CRDs that don't exist yet
- The plan fails with "API did not recognize GroupVersionKind"

**Solution:** Deploy in 2 stages:
1. Stage 1 installs CRDs via Helm
2. Stage 2 uses those CRDs for manifests

This follows operations best practices:
- Clear separation of concerns
- Independent updates (infrastructure vs. applications)
- Standard workflow (just `terraform apply`, no special flags)
- Easier troubleshooting

## See Full Documentation

Read `README.md` for complete details on architecture, verification, and troubleshooting.
