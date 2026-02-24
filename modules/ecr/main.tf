# ECR module: private registries with org-wide read, dev write, 60-day expiry, KMS encryption.
# Supports multiple repos (e.g. per-account proxy for Docker Hub). Destroy removes repos and KMS cleanly.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# KMS key for ECR encryption (required for cross-account read from org)
# When retain_kms_key_on_destroy = true we use a key with prevent_destroy so
# destroy only removes repos; next apply reuses the same key (no cancel-key-deletion).
# ------------------------------------------------------------------------------
locals {
  kms_policy = jsonencode({
    Version = "2012-10-17"
    Id      = "ecr-org-kms-policy"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowECRServiceToUseKey"
        Effect = "Allow"
        Principal = {
          Service = "ecr.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowOrgAccountsDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = var.org_id
          }
        }
      }
    ]
  })
}

# Key that is retained on destroy (lifecycle prevent_destroy)
resource "aws_kms_key" "ecr_retained" {
  count = var.use_custom_kms && var.retain_kms_key_on_destroy ? 1 : 0

  description             = "KMS key for ECR; org-wide decrypt for cross-account pull"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = local.kms_policy
}

# Key that is scheduled for deletion on destroy (default)
resource "aws_kms_key" "ecr" {
  count = var.use_custom_kms && !var.retain_kms_key_on_destroy ? 1 : 0

  description             = "KMS key for ECR; org-wide decrypt for cross-account pull"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days

  policy = local.kms_policy
}

resource "aws_kms_alias" "ecr_retained" {
  count = var.use_custom_kms && var.retain_kms_key_on_destroy ? 1 : 0

  name          = "alias/${var.kms_alias_prefix}ecr"
  target_key_id = aws_kms_key.ecr_retained[0].key_id
}

resource "aws_kms_alias" "ecr" {
  count = var.use_custom_kms && !var.retain_kms_key_on_destroy ? 1 : 0

  name          = "alias/${var.kms_alias_prefix}ecr"
  target_key_id = aws_kms_key.ecr[0].key_id
}

locals {
  ecr_kms_key_arn = var.use_custom_kms ? (var.retain_kms_key_on_destroy ? aws_kms_key.ecr_retained[0].arn : aws_kms_key.ecr[0].arn) : null
}

# ------------------------------------------------------------------------------
# ECR repositories
# ------------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true # Allow terraform destroy to remove repo even with images

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = local.ecr_kms_key_arn
  }

  tags = merge(var.tags, {
    Name = each.value
  })
}

# Lifecycle: expire images after N days (default 60)
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = toset(var.repository_names)

  repository = aws_ecr_repository.this[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire images older than ${var.image_expiration_days} days"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.image_expiration_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Repository policy: read from any account in org, write from dev + additional accounts
locals {
  push_account_ids = concat([var.dev_account_id], var.additional_push_account_ids)
  push_account_arns = [for id in local.push_account_ids : "arn:aws:iam::${id}:root"]
}

resource "aws_ecr_repository_policy" "this" {
  for_each = toset(var.repository_names)

  repository = aws_ecr_repository.this[each.value].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OrgRead"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = var.org_id
          }
        }
      },
      {
        Sid    = "Push"
        Effect = "Allow"
        Principal = {
          AWS = local.push_account_arns
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}
