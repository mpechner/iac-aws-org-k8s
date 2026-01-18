# S3 Buckets Module

This directory manages S3 buckets across AWS accounts with proper logging, versioning, lifecycle, and encryption.

## Structure

```
buckets/
├── modules/
│   └── s3-bucket/          # Reusable S3 bucket module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── dev-account/            # Dev account bucket deployment
    ├── main.tf
    ├── providers.tf
    ├── terraform.tf
    ├── variables.tf
    ├── outputs.tf
    └── example.tfvars
```

## Module Features

The `s3-bucket` module provides:
- AWS KMS encryption (default: `alias/aws/s3`)
- Versioning (configurable)
- Lifecycle policies for object and version expiration
- S3 access logging
- Public access blocking (always enabled)
- Bucket key optimization

## Dev Account Buckets

### Service Logging Bucket
**Name**: `mikey-s3-servicelogging-dev-us-west-2`

- **Purpose**: Centralized S3 access logs
- **Versioning**: Disabled
- **Lifecycle**: 90 days expiration
- **Logging**: Disabled (no logging on the logging bucket itself)
- **Encryption**: AWS managed KMS key (`alias/aws/s3`)

### RKE etcd Backups Bucket
**Name**: `mikey-dev-rke-etcd-backups`

- **Purpose**: RKE cluster etcd backups
- **Versioning**: Enabled
- **Lifecycle**: 365 days (both current and noncurrent versions)
- **Logging**: Enabled → service logging bucket
- **Log Prefix**: `[AccountId]/[Region]/[SourceBucket]/`
- **Encryption**: AWS managed KMS key (`alias/aws/s3`)

## Deployment

### Step 1: Create Buckets

```bash
cd buckets/dev-account
terraform init
terraform plan
terraform apply
```

### Step 2: Enable etcd Backups in RKE

The RKE cluster configuration has been updated to use `mikey-dev-rke-etcd-backups`:

```hcl
# RKE-cluster/dev-cluster/RKE/main.tf
module "rke-server" {
  # ...
  etcd_backup_enabled = true
  etcd_backup_bucket  = "mikey-dev-rke-etcd-backups"
}
```

Apply the RKE changes:

```bash
cd ../../RKE-cluster/dev-cluster/RKE
terraform apply
```

## Logging Format

Access logs are stored with this prefix pattern:
```
[SourceAccountId]/[SourceRegion]/[SourceBucket]/[YYYY]/[MM]/[DD]/[YYYY]-[MM]-[DD]-[hh]-[mm]-[ss]-[UniqueString]
```

Example log path:
```
REDACTED_ACCOUNT_ID/us-west-2/mikey-dev-rke-etcd-backups/2026/01/18/2026-01-18-12-00-00-ABC123DEF456
```

## Verification

```bash
# List buckets
aws s3 ls

# Check bucket versioning
aws s3api get-bucket-versioning --bucket mikey-dev-rke-etcd-backups

# Check bucket lifecycle
aws s3api get-bucket-lifecycle-configuration --bucket mikey-dev-rke-etcd-backups

# Check bucket encryption
aws s3api get-bucket-encryption --bucket mikey-dev-rke-etcd-backups

# Check bucket logging
aws s3api get-bucket-logging --bucket mikey-dev-rke-etcd-backups
```

## Adding More Buckets

To add buckets for other accounts or purposes, create a new directory:

```bash
mkdir -p buckets/prod-account
# Copy dev-account files and adjust
```

Or add to `buckets/dev-account/main.tf`:

```hcl
module "new_bucket" {
  source = "../modules/s3-bucket"

  bucket_name = "my-new-bucket"
  region      = local.region
  account_id  = local.account_id

  versioning_enabled            = true
  lifecycle_expiration_days     = 365
  
  enable_logging = true
  logging_bucket = module.service_logging_bucket.bucket_id
  logging_prefix = "${local.account_id}/${local.region}/my-new-bucket/"

  tags = {
    Name    = "my-new-bucket"
    Purpose = "Description"
  }
}
```
