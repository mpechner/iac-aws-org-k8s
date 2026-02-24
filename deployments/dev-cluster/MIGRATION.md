# Migration Guide - Old to New Deployment Structure

## What Changed

The ingress deployment was refactored from a single workspace with `deploy.sh` script to **two separate Terraform workspaces** for cleaner operations.

### Old Structure (❌ Deprecated)
```
deployments/dev-cluster/
├── main.tf              # Everything in one file
├── deploy.sh            # Required 2-stage script with -target flags
└── modules/ingress/     # Monolithic module
```

### New Structure (✅ Current)
```
deployments/dev-cluster/
├── 1-infrastructure/    # Stage 1: Helm charts
│   ├── main.tf
│   └── terraform.tfvars
├── 2-applications/      # Stage 2: Manifests + apps
│   ├── main.tf
│   └── terraform.tfvars
└── README.md           # Full documentation
```

## If You Have an Existing Deployment

### Option 1: Fresh Deployment (Recommended)

**Best for:** Development environments where downtime is acceptable

1. Destroy old deployment:
```bash
cd deployments/dev-cluster
terraform destroy
```

2. Deploy new structure:
```bash
cd 1-infrastructure
terraform init
terraform apply

cd ../2-applications
terraform init
terraform apply
```

### Option 2: State Migration (Advanced)

**Best for:** Production environments requiring zero downtime

This is complex and requires careful state manipulation. Contact DevOps team for assistance.

## Why This Change?

### Problem with Old Approach
- Used `terraform apply -target` flags (anti-pattern)
- Hidden complexity in `deploy.sh` script
- Harder to troubleshoot ("which target failed?")
- Not obvious from directory structure

### Benefits of New Approach
- ✅ **Standard Terraform workflow** - Just `terraform apply`
- ✅ **Clear separation** - Infrastructure vs. Applications
- ✅ **Independent operations** - Update apps without touching infrastructure
- ✅ **Self-documenting** - Directory structure shows the flow
- ✅ **Easier runbooks** - Two simple steps instead of script magic

## Technical Reason for Two Stages

Terraform's `kubernetes_manifest` validates CRDs during `terraform plan` **before** deployment. This means:

1. Stage 1 deploys Helm charts → installs CRDs in cluster
2. Stage 2 uses those CRDs → validates successfully

Without separation, Terraform would fail at plan time because CRDs don't exist yet.

## Questions?

See `README.md` for complete documentation.
