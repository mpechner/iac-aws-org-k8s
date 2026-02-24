# ECR module variables

variable "repository_names" {
  type        = list(string)
  description = "Names of ECR repositories to create (e.g. proxy-dockerhub, my-app). Each account can use its own repo for Docker Hub proxy."
}

variable "org_id" {
  type        = string
  description = "AWS Organizations ID (e.g. o-xxxxxxxx). Used for org-wide read access and KMS key policy."
}

variable "dev_account_id" {
  type        = string
  description = "AWS account ID allowed to push images (write access)."
}

variable "additional_push_account_ids" {
  type        = list(string)
  default     = []
  description = "Additional AWS account IDs allowed to push images (write access)."
}

variable "image_expiration_days" {
  type        = number
  default     = 60
  description = "Days after which repository images expire (lifecycle policy)."
}

variable "use_custom_kms" {
  type        = bool
  default     = true
  description = "Use a custom KMS key for ECR encryption so any account in the org can pull (decrypt). If false, uses AES256 (simpler but no cross-account KMS)."
}

variable "kms_alias_prefix" {
  type        = string
  default     = ""
  description = "Optional prefix for the KMS alias (e.g. 'dev-' -> alias/dev-ecr). Final alias is alias/<prefix>ecr."
}

variable "kms_deletion_window_days" {
  type        = number
  default     = 7
  description = "Days to wait before KMS key is deleted (7-30). Ignored when retain_kms_key_on_destroy = true."
}

variable "retain_kms_key_on_destroy" {
  type        = bool
  default     = false
  description = "When true, KMS key (and alias) are not destroyed on terraform destroy; repos are removed but the key stays so a later apply can recreate repos using the same key without manual cancel-key-deletion."
}

variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "Image tag mutability: MUTABLE or IMMUTABLE."
}

variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Scan images on push for vulnerabilities."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to ECR repositories and KMS key."
}
