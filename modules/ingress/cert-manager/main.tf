terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
  }
}

resource "helm_release" "cert_manager" {
  name             = var.name
  repository       = var.repository
  chart            = var.chart
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  timeout          = 300  # 5 minutes
  wait             = true
  wait_for_jobs    = true

  set = concat(
    [{
      name  = "installCRDs"
      value = var.install_crds ? "true" : "false"
    }],
    var.set
  )

  values = var.values
}


