terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
  }
}

resource "helm_release" "traefik" {
  name             = var.name
  repository       = var.repository
  chart            = var.chart
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  timeout          = 600  # 10 minutes to allow for load balancer provisioning
  wait             = true
  wait_for_jobs    = true

  # Combine default configuration with user-provided set values
  set = concat(
    [
      {
        name  = "service.type"
        value = var.service_type
      },
      {
        name  = "dashboard.enabled"
        value = "true"
      },
      {
        name  = "api.dashboard"
        value = "true"
      },
      {
        name  = "api.insecure"
        value = "true"
      },
      {
        name  = "ports.web.expose"
        value = "true"
      },
      {
        name  = "ports.websecure.expose"
        value = "true"
      }
    ],
    var.set
  )

  values = var.values
}


