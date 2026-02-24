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

variable "route53_domain" {
  type        = string
  description = "Route53 hosted zone domain name"
}

variable "letsencrypt_environment" {
  type        = string
  default     = "staging"
  description = "prod or staging"
}

# OpenVPN TLS cert (cert-manager + CronJob to Secrets Manager)
variable "openvpn_cert_enabled" {
  type        = bool
  default     = true
  description = "If true, create ClusterIssuer, Certificate, RBAC, and optionally the publisher CronJob."
}

variable "openvpn_cert_hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for the domain; scopes the cert-manager DNS-01 solver."
  default     = ""
}

variable "openvpn_cert_letsencrypt_email" {
  type        = string
  description = "Email for the Let's Encrypt ACME account (cert expiry notifications)."
  default     = ""
}

variable "openvpn_cert_publisher_image" {
  type        = string
  description = "ECR image URI for the cert publisher CronJob (e.g. REDACTED_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/openvpn-dev:latest). Leave empty to skip CronJob creation."
  default     = ""
}
