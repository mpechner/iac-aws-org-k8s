output "vpn_fqdn" {
  value       = local.enabled ? local.vpn_fqdn : null
  description = "VPN FQDN (vpn.<route53_domain>)."
}

output "namespace" {
  value       = local.enabled ? "openvpn-certs" : null
  description = "Namespace for the Certificate and CronJob."
}

output "tls_secret_name" {
  value       = local.enabled ? local.tls_secret : null
  description = "Name of the TLS Secret created by cert-manager in the openvpn-certs namespace."
}

output "secrets_manager_name" {
  value       = local.enabled ? local.secrets_manager_name : null
  description = "AWS Secrets Manager path where the published cert is stored (openvpn/<environment>)."
}

output "clusterissuer_name" {
  value       = local.enabled ? "letsencrypt-vpn-${var.letsencrypt_environment}" : null
  description = "Name of the dedicated cert-manager ClusterIssuer for the VPN certificate."
}

output "cronjob_name" {
  value       = local.enabled && var.publisher_image != "" ? "openvpn-publish-cert-to-secretsmanager" : null
  description = "Name of the publisher CronJob (null when publisher_image is not set)."
}
