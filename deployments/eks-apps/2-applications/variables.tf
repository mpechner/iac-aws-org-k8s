variable "account_id" {
  type        = string
  description = "AWS account ID for the dev account"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "cluster_name" {
  type    = string
  default = "dev-eks"
}

# Remote state: EKS cluster (endpoint + CA cert read automatically from 2-cluster state)
variable "cluster_state_bucket" {
  type    = string
  default = "mikey-com-terraformstate"
}

variable "cluster_state_key" {
  type    = string
  default = "eks-dev/2-cluster"
}

variable "cluster_state_region" {
  type    = string
  default = "us-east-1"
}

variable "route53_domain" {
  type    = string
  default = "dev.foobar.support"
}

variable "letsencrypt_environment" {
  type        = string
  default     = "prod"
  description = "staging or prod"
}

variable "letsencrypt_email" {
  type        = string
  description = "Email for Let's Encrypt certificate notifications"
}

variable "grafana_admin_password" {
  type        = string
  description = "Initial Grafana admin password (stored in k8s secret 'grafana-admin')"
  sensitive   = true
}

# OpenVPN TLS cert (tls-issue module + IRSA publisher)
variable "openvpn_cert_enabled" {
  type        = bool
  default     = true
  description = "If true, create ClusterIssuer, Certificate, RBAC, and optionally the publisher CronJob."
}

variable "openvpn_cert_hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for the VPN domain; scopes the cert-manager DNS-01 solver."
  default     = ""
}

variable "openvpn_cert_letsencrypt_email" {
  type        = string
  description = "Email for the Let's Encrypt ACME account (cert expiry notifications)."
  default     = ""
}

variable "openvpn_cert_publisher_image" {
  type        = string
  description = "Cert publisher CronJob image, as <repo>:<tag> (e.g., \"openvpn-dev:latest\"). The full ECR URI is constructed in openvpn-cert.tf from account_id + aws_region + this value, so the tfvars file does not hold a hardcoded account ID. Leave empty to skip CronJob creation."
  default     = ""
}

variable "openvpn_cert_publisher_irsa_role_arn" {
  type        = string
  description = "Optional override for the IRSA role ARN used by the publisher CronJob SA. Normally left empty — openvpn-cert.tf auto-constructs the ARN from account_id + cluster_name to match the role created in 3-karpenter/irsa.tf. Set this only if the role lives under a custom name or in a different account."
  default     = ""
}
