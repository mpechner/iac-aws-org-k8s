# ECR - dev - outputs

output "repository_urls" {
  description = "ECR repository URLs for docker push/pull"
  value       = module.ecr.repository_urls
}

output "repository_arns" {
  description = "ECR repository ARNs"
  value       = module.ecr.repository_arns
}

output "kms_key_arn" {
  description = "KMS key ARN used for ECR encryption"
  value       = module.ecr.kms_key_arn
}
