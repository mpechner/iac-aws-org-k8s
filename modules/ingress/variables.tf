# Enable flags
variable "traefik_enabled" { type = bool default = true }
variable "external_dns_enabled" { type = bool default = false }
variable "cert_manager_enabled" { type = bool default = false }

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


