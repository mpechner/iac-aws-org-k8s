# ECR module outputs

output "repository_urls" {
  description = "Map of repository name to ECR registry URL (for docker push/pull)."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository name to ARN."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "repository_registry_id" {
  description = "Registry ID (account ID) where repos live."
  value       = length(aws_ecr_repository.this) > 0 ? values(aws_ecr_repository.this)[0].registry_id : null
}

output "kms_key_id" {
  description = "ID of the KMS key used for ECR encryption (null if use_custom_kms = false)."
  value       = var.use_custom_kms ? (var.retain_kms_key_on_destroy ? aws_kms_key.ecr_retained[0].key_id : aws_kms_key.ecr[0].key_id) : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for ECR encryption (null if use_custom_kms = false)."
  value       = var.use_custom_kms ? (var.retain_kms_key_on_destroy ? aws_kms_key.ecr_retained[0].arn : aws_kms_key.ecr[0].arn) : null
}

output "kms_alias" {
  description = "Alias of the KMS key (e.g. alias/ecr). Null if use_custom_kms = false."
  value       = var.use_custom_kms ? (var.retain_kms_key_on_destroy ? aws_kms_alias.ecr_retained[0].name : aws_kms_alias.ecr[0].name) : null
}
