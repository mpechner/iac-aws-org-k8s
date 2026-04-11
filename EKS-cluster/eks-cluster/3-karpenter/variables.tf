variable "account_id" {
  description = "AWS account ID for the dev account"
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
  description = "EKS cluster name — must match what was created in 2-cluster"
  type        = string
  default     = "dev-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version — must match 2-cluster"
  type        = string
  default     = "1.35"
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.11.0"
}

# Remote state references
variable "iam_state_bucket" {
  type    = string
  default = "mikey-com-terraformstate"
}

variable "iam_state_key" {
  type    = string
  default = "eks-dev/1-iam"
}

variable "iam_state_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_state_bucket" {
  type    = string
  default = "mikey-com-terraformstate"
}

variable "cluster_state_key" {
  type    = string
  default = "eks-dev/2-cluster"
}

variable "cluster_state_region" {
  type    = string
  default = "us-east-1"
}
