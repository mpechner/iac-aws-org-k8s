variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "route53_domain" {
  type        = string
  description = "Route53 hosted zone domain name"
}

variable "letsencrypt_email" {
  type        = string
  default     = "mikey@mikey.com"
  description = "Email for Let's Encrypt certificate notifications"
}

variable "letsencrypt_environment" {
  type        = string
  default     = "staging"
  description = "Let's Encrypt environment: prod or staging"
}

variable "traefik_namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace where Traefik is deployed"
}

variable "ingresses" {
  type = map(object({
    namespace           = string
    host                = string
    service_name        = string
    service_port        = number
    path                = optional(string)
    path_type           = optional(string)
    ingress_class_name  = optional(string)
    tls_secret_name     = optional(string)
    cluster_issuer      = optional(string)
    backend_tls_enabled = optional(bool)
    annotations         = optional(map(string))
  }))
  description = "Map of ingress configurations"
  default     = {}
}
