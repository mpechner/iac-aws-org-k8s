# Enable flags
variable "traefik_enabled" { type = bool default = true }
variable "external_dns_enabled" { type = bool default = true }
variable "cert_manager_enabled" { type = bool default = true }

# AWS Region and Route53 Domain
variable "aws_region" { type = string default = "us-west-2" }
variable "route53_zone_id" { type = string description = "Route53 hosted zone ID for DNS records" }
variable "route53_domain" { type = string description = "Route53 hosted zone domain name" }
variable "route53_assume_role_arn" {
  type        = string
  default     = null
  description = "Optional IAM role ARN for cross-account Route53 access"
}

# Traefik
variable "traefik_name" { type = string default = "traefik" }
variable "traefik_namespace" { type = string default = "kube-system" }
variable "traefik_create_namespace" { type = bool default = true }
variable "traefik_repository" { type = string default = "https://traefik.github.io/charts" }
variable "traefik_chart" { type = string default = "traefik" }
variable "traefik_chart_version" { type = string default = "24.0.0" }
variable "traefik_service_type" { type = string default = "LoadBalancer" }
variable "traefik_set" {
  type = list(object({ name = string, value = string, type = optional(string) }))
  default = []
}
variable "traefik_values" { type = list(string) default = [] }

# External DNS
variable "external_dns_name" { type = string default = "external-dns" }
variable "external_dns_namespace" { type = string default = "kube-system" }
variable "external_dns_create_namespace" { type = bool default = true }
variable "external_dns_repository" { type = string default = "https://kubernetes-sigs.github.io/external-dns/" }
variable "external_dns_chart" { type = string default = "external-dns" }
variable "external_dns_chart_version" { type = string default = "1.15.0" }
variable "external_dns_set" {
  type = list(object({ name = string, value = string, type = optional(string) }))
  default = []
}
variable "external_dns_values" { type = list(string) default = [] }

# Cert Manager
variable "cert_manager_name" { type = string default = "cert-manager" }
variable "cert_manager_namespace" { type = string default = "cert-manager" }
variable "cert_manager_create_namespace" { type = bool default = true }
variable "cert_manager_repository" { type = string default = "https://charts.jetstack.io" }
variable "cert_manager_chart" { type = string default = "cert-manager" }
variable "cert_manager_chart_version" { type = string default = "v1.15.3" }
variable "cert_manager_install_crds" { type = bool default = true }
variable "cert_manager_set" {
  type = list(object({ name = string, value = string, type = optional(string) }))
  default = []
}
variable "cert_manager_values" { type = list(string) default = [] }

# Let's Encrypt
variable "letsencrypt_email" { type = string description = "Email for Let's Encrypt certificate notifications" }
variable "letsencrypt_environment" { type = string default = "prod" description = "prod or staging" }

# Internal ALB Configuration
variable "enable_internal_alb" {
  type        = bool
  default     = false
  description = "Enable internal ALB for Traefik dashboard and internal services"
}

variable "internal_service_domains" {
  type        = list(string)
  default     = []
  description = "List of internal-only domains (e.g., traefik.dev.foobar.support, rke.dev.foobar.support)"
}

variable "public_subnets" {
  type        = list(string)
  default     = []
  description = "List of public subnet IDs for internet-facing load balancer"
}

variable "private_subnets" {
  type        = list(string)
  default     = []
  description = "List of private subnet IDs for internal load balancer"
}

# Managed Ingresses
variable "ingresses" {
  description = "Ingress definitions to create in the cluster"
  type = map(object({
    namespace          = optional(string, "default")
    host               = string
    service_name       = string
    service_port       = number
    path               = optional(string, "/")
    path_type          = optional(string, "Prefix")
    ingress_class_name = optional(string, "traefik")
    tls_secret_name    = optional(string)
    cluster_issuer     = optional(string)
    annotations        = optional(map(string), {})
    backend_tls_enabled = optional(bool, true)  # Always enable backend TLS by default
  }))
  default = {}
}


