# Consumed by 2-cluster and 3-karpenter via terraform_remote_state

output "cluster_role_arn" {
  description = "IAM role ARN for the EKS control plane"
  value       = aws_iam_role.eks_cluster.arn
}

output "bootstrap_node_role_arn" {
  description = "IAM role ARN for the bootstrap managed node group"
  value       = aws_iam_role.bootstrap_nodes.arn
}

output "karpenter_node_role_arn" {
  description = "IAM role ARN for Karpenter-launched EC2 nodes"
  value       = aws_iam_role.karpenter_node.arn
}

output "karpenter_node_role_name" {
  description = "IAM role name for Karpenter-launched EC2 nodes (for aws-auth ConfigMap)"
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_node_instance_profile_name" {
  description = "Instance profile name for Karpenter EC2NodeClass"
  value       = aws_iam_instance_profile.karpenter_node.name
}

output "kms_key_arn" {
  description = "KMS key ARN for EKS secrets encryption"
  value       = aws_kms_key.eks_secrets.arn
}

output "kms_key_id" {
  description = "KMS key ID"
  value       = aws_kms_key.eks_secrets.key_id
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue name for Karpenter interruption handling"
  value       = aws_sqs_queue.karpenter_interruption.name
}

output "karpenter_interruption_queue_arn" {
  description = "SQS queue ARN for Karpenter interruption handling"
  value       = aws_sqs_queue.karpenter_interruption.arn
}
