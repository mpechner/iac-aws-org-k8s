variable "account_id" {
  type        = string
  description = "AWS account ID for the dev account"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "cluster_name" {
  type    = string
  default = "dev-eks"
}

# VPC subnet discovery
variable "vpc_name" {
  type    = string
  default = "dev"
}

variable "public_subnet_names" {
  type    = list(string)
  default = ["dev-pub-us-west-2a", "dev-pub-us-west-2b", "dev-pub-us-west-2c"]
}

# Internal NLB uses dev-priv-* subnets only (not dev-eks-* which are for nodes)
variable "private_subnet_names" {
  type    = list(string)
  default = ["dev-priv-us-west-2a", "dev-priv-us-west-2b", "dev-priv-us-west-2c"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.8.0.0/24", "10.8.64.0/24", "10.8.128.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.8.16.0/20", "10.8.80.0/20", "10.8.144.0/20"]
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for dev.foobar.support"
}

variable "route53_domain" {
  type    = string
  default = "dev.foobar.support"
}

variable "letsencrypt_email" {
  type        = string
  description = "Email for Let's Encrypt certificate notifications"
}

variable "letsencrypt_environment" {
  type    = string
  default = "prod"
}

# Remote state (shared bucket/region for all EKS state reads)
variable "karpenter_state_bucket" {
  type    = string
  default = "mikey-com-terraformstate"
}

variable "karpenter_state_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_state_key" {
  type    = string
  default = "eks-dev/2-cluster"
}

variable "karpenter_state_key" {
  type    = string
  default = "eks-dev/3-karpenter"
}
