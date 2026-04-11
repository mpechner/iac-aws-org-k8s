output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_cert" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_arn" {
  description = "OIDC provider ARN — used by 3-karpenter for IRSA trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer" {
  description = "OIDC issuer without https:// prefix — used by 3-karpenter for IRSA trust policies"
  value       = local.oidc_issuer
}

output "eks_subnet_ids" {
  description = "Subnet IDs used by the EKS cluster"
  value       = local.eks_subnet_ids
}

output "bootstrap_node_group_name" {
  description = "Name of the Karpenter bootstrap managed node group"
  value       = aws_eks_node_group.karpenter_bootstrap.node_group_name
}

output "kubeconfig_instructions" {
  description = "Instructions for setting up kubectl access to this EKS cluster"
  value       = <<-EOT
    To configure kubectl access, run:

    aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name} --alias ${var.cluster_name} --assume-role-arn arn:aws:iam::${var.account_id}:role/terraform-execute

    Then (for your own shell only — the eks-apps terraform stack does not depend on current-context):
    kubectl config use-context ${var.cluster_name}
    kubectl get nodes
  EOT
}
