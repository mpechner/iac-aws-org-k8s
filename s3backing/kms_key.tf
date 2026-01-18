resource "aws_kms_key" "org_shared_key" {
  description             = "KMS key for use by all accounts in Org r-u7bj"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = templatefile("${path.module}/config/kms-policy.json.tftpl", {
    account_id = data.aws_caller_identity.current.account_id
    org_id     = "r-u7bj"
  })
}

resource "aws_kms_alias" "org_shared_key_alias" {
  name          = "alias/org-shared-s3-key"
  target_key_id = aws_kms_key.org_shared_key.key_id
}

data "aws_caller_identity" "current" {}
