variable "route53_domain" {
  type        = string
  description = "Route53 hosted zone domain name (VPN FQDN will be vpn.<domain>)."
}

variable "hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone ID; scopes the cert-manager ClusterIssuer DNS-01 solver to this zone."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment label (e.g. dev, staging, prod). Determines Secrets Manager path: openvpn/<environment>."
}

variable "letsencrypt_environment" {
  type        = string
  default     = "prod"
  description = "Let's Encrypt environment: prod or staging (controls ACME server URL)."
}

variable "letsencrypt_email" {
  type        = string
  description = "Email address for Let's Encrypt ACME account notifications."
}

variable "aws_region" {
  type        = string
  description = "AWS region for the publisher CronJob and cert-manager Route53 solver (e.g. us-west-2)."
}

variable "enabled" {
  type        = bool
  default     = true
  description = "If true, create ClusterIssuer, namespace, Certificate, RBAC, and optionally CronJob."
}

variable "publisher_image" {
  type        = string
  default     = ""
  description = "Container image for the cert publisher CronJob (e.g. <account>.dkr.ecr.<region>.amazonaws.com/openvpn-dev:latest). Leave empty to skip CronJob creation."
}

