# S3 Bucket Module Variables

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket"
}

variable "region" {
  type        = string
  description = "AWS region for the bucket"
}

variable "account_id" {
  type        = string
  description = "AWS account ID"
}

variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Enable versioning on the bucket"
}

variable "lifecycle_expiration_days" {
  type        = number
  default     = 365
  description = "Number of days after which objects expire"
}

variable "lifecycle_noncurrent_expiration_days" {
  type        = number
  default     = 365
  description = "Number of days after which noncurrent versions expire"
}

variable "enable_logging" {
  type        = bool
  default     = false
  description = "Enable S3 access logging"
}

variable "logging_bucket" {
  type        = string
  default     = ""
  description = "Target bucket for access logs"
}

variable "logging_prefix" {
  type        = string
  default     = ""
  description = "Prefix for access log objects"
}

variable "kms_key_id" {
  type        = string
  default     = ""
  description = "KMS key ID for bucket encryption (empty = use AWS managed key)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the bucket"
}
