variable "name" { type = string default = "cert-manager" }
variable "namespace" { type = string default = "cert-manager" }
variable "create_namespace" { type = bool default = true }
variable "repository" { type = string default = "https://charts.jetstack.io" }
variable "chart" { type = string default = "cert-manager" }
variable "chart_version" { type = string default = "v1.15.3" }
variable "install_crds" { type = bool default = true }

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


