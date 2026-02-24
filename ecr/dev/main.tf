# ECR - dev - module

module "ecr" {
  source = "../../modules/ecr"

  repository_names           = var.repository_names
  org_id                     = var.org_id
  dev_account_id             = var.account_id
  additional_push_account_ids = var.additional_push_account_ids
  image_expiration_days      = var.image_expiration_days
  use_custom_kms             = var.use_custom_kms
  kms_deletion_window_days   = 7
  retain_kms_key_on_destroy  = var.retain_kms_key_on_destroy

  tags = var.tags
}
