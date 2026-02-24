# ECR - dev - variables

variable "account_id" {
  description = "AWS account ID (dev account; used for assume role and as dev_account_id for write access)"
  default = "REDACTED_ACCOUNT_ID"
}

variable "org_id" {
  description = "AWS Organizations ID (e.g. from Organization outputs: org-id)"
  default = "o-v2z2jzv9f6"
}

variable "region" {
  description = "AWS region for ECR"
  type        = string
  default     = "us-west-2"
}

variable "repository_names" {
  description = "ECR repository names to create (e.g. proxy-dockerhub, my-app)"
  default     = ["openvpn-dev"]
}

variable "additional_push_account_ids" {
  description = "Additional AWS account IDs allowed to push images"
  type        = list(string)
  default     = ["REDACTED_ACCOUNT_ID"]
}

variable "image_expiration_days" {
  description = "Days after which images expire"
  type        = number
  default     = 60
}

variable "use_custom_kms" {
  description = "Use custom KMS key for encryption (required for org-wide cross-account pull)"
  type        = bool
  default     = true
}

variable "retain_kms_key_on_destroy" {
  description = "When true, destroy removes only ECR repos; KMS key is kept so next apply reuses it (no manual cancel-key-deletion)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
