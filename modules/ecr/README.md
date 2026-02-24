# ECR Module

Private ECR registries with:

- **Read**: Any account in your AWS Organization can pull images.
- **Write**: Only the configured dev (or single-writer) account can push.
- **Lifecycle**: Images expire after 60 days (configurable).
- **Encryption**: Optional custom KMS key so org accounts can decrypt when pulling cross-account; otherwise AES256.
- **Destroy**: Repositories use `force_delete`. KMS key is either scheduled for deletion (default) or retained so a later apply reuses it (`retain_kms_key_on_destroy = true`).

Use one or more repository names so each account (or use case) can have its own repo, e.g. for Docker Hub pull-through proxy or app images.

## Usage

```hcl
module "ecr" {
  source = "../modules/ecr"  # or your path to modules/ecr

  repository_names       = ["proxy-dockerhub", "my-app"]
  org_id                 = "o-xxxxxxxx"       # AWS Organizations ID
  dev_account_id         = "123456789012"     # Account allowed to push
  image_expiration_days  = 60
  use_custom_kms         = true
  kms_deletion_window_days = 7

  tags = { Environment = "dev" }
}
```

## Cross-account pull

Callers in other org accounts need:

1. **Repository policy** (handled by this module): Org principals get `BatchGetImage`, `GetDownloadUrlForLayer`, `BatchCheckLayerAvailability`.
2. **KMS** (when `use_custom_kms = true`): The module’s key policy allows any principal in the org to `kms:Decrypt`, `kms:GenerateDataKey*`, `kms:DescribeKey` so ECR can decrypt layers in their account.

IAM in the *pulling* account still needs `ecr:GetAuthorizationToken` (registry-level) plus any IAM you use to allow `ecr:BatchGetImage` etc. on the repo (or rely on the resource policy only with appropriate principal).

## Destroy

- ECR repos use `force_delete = true`, so they are removed even when they contain images.
- **Default (`retain_kms_key_on_destroy = false`)**: The KMS key is scheduled for deletion (7–30 day window). After the window, AWS deletes the key. A later `terraform apply` creates a new key.
- **Retain key (`retain_kms_key_on_destroy = true`)**: The KMS key (and alias) are not destroyed. `terraform destroy` removes repos and policies, then errors on the key (lifecycle `prevent_destroy`). The key stays in AWS and in state. A later `terraform apply` recreates repos using the same key—no manual `cancel-key-deletion` needed.

## Inputs

| Name | Description | Default |
|------|-------------|--------|
| repository_names | List of ECR repository names | (required) |
| org_id | AWS Organizations ID | (required) |
| dev_account_id | Account ID allowed to push | (required) |
| image_expiration_days | Days after which images expire | 60 |
| use_custom_kms | Use custom KMS for org cross-account pull | true |
| kms_alias_prefix | Prefix for KMS alias | "" |
| kms_deletion_window_days | KMS key deletion window (7–30) | 7 |
| retain_kms_key_on_destroy | Keep KMS key on destroy so next apply reuses it | false |
| image_tag_mutability | MUTABLE or IMMUTABLE | MUTABLE |
| scan_on_push | Enable image scanning on push | true |
| tags | Tags for repos and key | {} |

## Outputs

- `repository_urls` – Map of name → repository URL (for `docker push`/`pull`).
- `repository_arns` – Map of name → ARN.
- `repository_registry_id` – Registry (account) ID.
- `kms_key_id`, `kms_key_arn`, `kms_alias` – Set when `use_custom_kms = true`.
