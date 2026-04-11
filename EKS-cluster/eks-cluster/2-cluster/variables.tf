variable "account_id" {
  description = "AWS account ID for the dev account"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — OpenVPN NATs VPN client traffic through the VPC so this is the source for EKS API access"
  type        = string
  default     = "10.8.0.0/16"
}

variable "admin_role_arn" {
  description = "IAM role ARN granted cluster-admin access (e.g. SSO AdministratorAccess role)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "dev-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.35"
}

# Remote state references
variable "iam_state_bucket" {
  description = "S3 bucket holding the 1-iam state"
  type        = string
  default     = "mikey-com-terraformstate"
}

variable "iam_state_key" {
  description = "S3 key for the 1-iam state"
  type        = string
  default     = "eks-dev/1-iam"
}

variable "iam_state_region" {
  description = "Region of the state bucket"
  type        = string
  default     = "us-east-1"
}

variable "vpc_state_bucket" {
  description = "S3 bucket holding the VPC state"
  type        = string
  default     = "mikey-com-terraformstate"
}

variable "vpc_state_key" {
  description = "S3 key for the VPC state"
  type        = string
  default     = "vpc/dev"
}

variable "vpc_state_region" {
  description = "Region of the VPC state bucket"
  type        = string
  default     = "us-east-1"
}

# Bootstrap node group — hosts Karpenter controller only
variable "bootstrap_instance_type" {
  description = "Instance type for the Karpenter bootstrap node group"
  type        = string
  default     = "t3.medium"
}

variable "bootstrap_node_count" {
  description = "Number of bootstrap nodes — 1 per AZ (3 subnets = 3 nodes)"
  type        = number
  default     = 3
}
