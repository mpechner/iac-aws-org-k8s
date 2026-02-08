variable "account_id" {
  type    = string
  default = "REDACTED_ACCOUNT_ID"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_assume_role_arn" {
  type    = string
  default = "arn:aws:iam::REDACTED_ACCOUNT_ID:role/terraform-execute"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for subnet lookups"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for DNS records"
}

variable "route53_domain" {
  type        = string
  description = "Route53 hosted zone domain name"
}

variable "route53_assume_role_arn" {
  type        = string
  default     = null
  description = "Optional IAM role ARN for cross-account Route53 access"
}

variable "letsencrypt_email" {
  type        = string
  description = "Email for Let's Encrypt certificate notifications"
}

variable "letsencrypt_environment" {
  type        = string
  default     = "staging"
  description = "prod or staging"
}

