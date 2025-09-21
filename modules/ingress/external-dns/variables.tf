variable "name" { type = string default = "external-dns" }
variable "namespace" { type = string default = "kube-system" }
variable "create_namespace" { type = bool default = true }
variable "repository" { type = string default = "https://kubernetes-sigs.github.io/external-dns/" }
variable "chart" { type = string default = "external-dns" }
variable "chart_version" { type = string default = "1.15.0" }

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


