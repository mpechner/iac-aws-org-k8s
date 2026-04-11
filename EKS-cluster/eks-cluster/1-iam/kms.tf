# KMS key for EKS secrets envelope encryption.
# Encrypts all Kubernetes secrets at rest in etcd.

resource "aws_kms_key" "eks_secrets" {
  description             = "EKS secrets encryption for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Full control for account root — required for all KMS keys
      {
        Sid    = "RootFullControl"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # Allow terraform-execute (the deployer) to administer the key
      {
        Sid    = "KeyAdminAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:role/terraform-execute"
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
        ]
        Resource = "*"
      },
      # Allow EKS to use the key for secrets encryption/decryption
      {
        Sid    = "EKSSecretsEncryption"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.eks_cluster.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.cluster_name}-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}
