# Nginx sample site module outputs

output "namespace" {
  description = "Namespace where nginx is deployed"
  value       = local.namespace
}

output "service_name" {
  description = "Name of the nginx service"
  value       = kubernetes_service.this.metadata[0].name
}

output "service_port" {
  description = "Port of the nginx service"
  value       = 443
}

output "ingress_name" {
  description = "Name of the ingress (managed by ingress module)"
  value       = null
}

output "hostname" {
  description = "Hostname of the site"
  value       = var.hostname
}

output "url" {
  description = "Full URL of the site"
  value       = var.cluster_issuer != null ? "https://${var.hostname}" : "http://${var.hostname}"
}
