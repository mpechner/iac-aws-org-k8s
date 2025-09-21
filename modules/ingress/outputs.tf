output "traefik_release" {
  value = var.traefik_enabled ? {
    name      = module.traefik[0].name
    namespace = module.traefik[0].namespace
    version   = module.traefik[0].version
  } : null
}

output "external_dns_release" {
  value = var.external_dns_enabled ? {
    name      = module.external_dns[0].name
    namespace = module.external_dns[0].namespace
    version   = module.external_dns[0].version
  } : null
}

output "cert_manager_release" {
  value = var.cert_manager_enabled ? {
    name      = module.cert_manager[0].name
    namespace = module.cert_manager[0].namespace
    version   = module.cert_manager[0].version
  } : null
}


