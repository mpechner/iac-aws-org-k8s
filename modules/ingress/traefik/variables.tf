variable "name" { type = string default = "traefik" }
variable "namespace" { type = string default = "kube-system" }
variable "create_namespace" { type = bool default = true }
variable "repository" { type = string default = "https://traefik.github.io/charts" }
variable "chart" { type = string default = "traefik" }
variable "chart_version" { type = string default = "24.0.0" }
variable "service_type" { type = string default = "LoadBalancer" }

variable "set" {
  description = "List of set values for helm chart"
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default = []
}

variable "values" {
  description = "Raw YAML values blocks"
  type        = list(string)
  default     = []
}


