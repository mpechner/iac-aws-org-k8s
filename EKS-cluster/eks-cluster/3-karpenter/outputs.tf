# IRSA role ARNs — consumed by deployments/eks-apps/1-infrastructure

output "irsa_external_dns_role_arn" {
  description = "IRSA role ARN for external-dns"
  value       = aws_iam_role.irsa_external_dns.arn
}

output "irsa_cert_manager_role_arn" {
  description = "IRSA role ARN for cert-manager"
  value       = aws_iam_role.irsa_cert_manager.arn
}

output "irsa_traefik_role_arn" {
  description = "IRSA role ARN for Traefik"
  value       = aws_iam_role.irsa_traefik.arn
}

output "irsa_keda_role_arn" {
  description = "IRSA role ARN for KEDA"
  value       = aws_iam_role.irsa_keda.arn
}

output "irsa_aws_lbc_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.irsa_aws_lbc.arn
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN"
  value       = local.oidc_arn
}

output "irsa_openvpn_cert_publisher_role_arn" {
  description = "IRSA role ARN for the OpenVPN cert publisher CronJob"
  value       = aws_iam_role.irsa_openvpn_cert_publisher.arn
}
