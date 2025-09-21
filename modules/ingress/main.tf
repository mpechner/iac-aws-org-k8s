module "traefik" {
  count = var.traefik_enabled ? 1 : 0
  source = "./traefik"

  name             = var.traefik_name
  namespace        = var.traefik_namespace
  create_namespace = var.traefik_create_namespace
  repository       = var.traefik_repository
  chart            = var.traefik_chart
  chart_version    = var.traefik_chart_version
  service_type     = var.traefik_service_type
  set              = var.traefik_set
  values           = var.traefik_values
}

module "external_dns" {
  count = var.external_dns_enabled ? 1 : 0
  source = "./external-dns"

  name             = var.external_dns_name
  namespace        = var.external_dns_namespace
  create_namespace = var.external_dns_create_namespace
  repository       = var.external_dns_repository
  chart            = var.external_dns_chart
  chart_version    = var.external_dns_chart_version
  set              = var.external_dns_set
  values           = var.external_dns_values
}

module "cert_manager" {
  count = var.cert_manager_enabled ? 1 : 0
  source = "./cert-manager"

  name             = var.cert_manager_name
  namespace        = var.cert_manager_namespace
  create_namespace = var.cert_manager_create_namespace
  repository       = var.cert_manager_repository
  chart            = var.cert_manager_chart
  chart_version    = var.cert_manager_chart_version
  install_crds     = var.cert_manager_install_crds
  set              = var.cert_manager_set
  values           = var.cert_manager_values
}


