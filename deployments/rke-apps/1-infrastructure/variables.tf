variable "account_id" {
  type        = string
  description = "AWS account ID"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_assume_role_arn" {
  type        = string
  description = "IAM role ARN for Terraform to assume"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "kubeconfig_context" {
  type        = string
  default     = "dev-rke2"
  description = "Kubeconfig context name for the RKE2 cluster. Pinned so the provider never reads current-context (which silently flips when you run aws eks update-kubeconfig). Matches the name written by scripts/setup-k9s.sh."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for subnet lookups (ignored if vpc_name is set)"
  default     = null
}

variable "vpc_name" {
  type        = string
  default     = "dev"
  description = "VPC tag Name to look up (same as RKE cluster). When set, used instead of vpc_id so subnets are found in the same VPC."
}

# Subnet names must match VPC/dev (tag Name). Used for reliable discovery so we find and annotate correctly.
variable "public_subnet_names" {
  type        = list(string)
  default     = ["dev-pub-us-west-2a", "dev-pub-us-west-2b", "dev-pub-us-west-2c"]
  description = "Public subnet Name tags for discovery. Must match VPC."
}

variable "private_subnet_names" {
  type        = list(string)
  default     = ["dev-priv-us-west-2a", "dev-priv-us-west-2b", "dev-priv-us-west-2c"]
  description = "Private subnet Name tags for internal NLB (dev-priv-* only; exclude dev-rke-*). Must match VPC."
}

# Optional: pass subnet IDs from VPC outputs to skip data source lookups
variable "public_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Public subnet IDs for NLB placement. If set, used instead of data source lookup."
}

variable "private_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Private subnet IDs for internal NLB placement. If set, used instead of data source lookup."
}

# CIDR fallback when tag-based lookup returns no subnets (e.g. VPC created before kubernetes.io/role tags)
variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.8.0.0/24", "10.8.64.0/24", "10.8.128.0/24"]
  description = "Public subnet CIDRs for fallback subnet discovery. Must match VPC layout."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.8.16.0/20", "10.8.80.0/20", "10.8.144.0/20", "10.8.192.0/20", "10.8.208.0/20", "10.8.224.0/20"]
  description = "Private subnet CIDRs for fallback subnet discovery. Must match VPC layout."
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for DNS records"
}

variable "route53_domain" {
  type        = string
  description = "Route53 hosted zone domain name"
}

variable "route53_assume_role_arn" {
  type        = string
  default     = null
  description = "Optional IAM role ARN for cross-account Route53 access"
}

variable "letsencrypt_email" {
  type        = string
  description = "Email for Let's Encrypt certificate notifications"
}

variable "letsencrypt_environment" {
  type        = string
  default     = "staging"
  description = "prod or staging"
}

variable "cluster_name" {
  type        = string
  default     = "dev-cluster"
  description = "Name of the Kubernetes cluster"
}

variable "attach_to_node_role" {
  type        = bool
  default     = true
  description = "Whether to automatically attach the LB controller policy to the node IAM role"
}

variable "node_iam_role_name" {
  type        = string
  default     = "rke-nodes-role"
  description = "Name of the RKE server node IAM role (required if attach_to_node_role is true)"
}

# Patch node providerIDs to AWS format. Not needed when using IP target type (default).
# RKE2 sets providerID to rke2://hostname at boot; Kubernetes forbids changing non-empty providerIDs.
variable "patch_node_provider_ids" {
  type        = bool
  default     = false
  description = "When true, patch RKE2 node providerIDs to aws:///az/instance-id. Only works on fresh nodes with empty providerID."
}
