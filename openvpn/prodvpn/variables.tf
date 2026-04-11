# OpenVPN prod environment variables

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "ami_id" {
  description = "AMI ID for OpenVPN Access Server. Leave empty to use the latest from AWS Marketplace."
  type        = string
  default     = ""
}

variable "account_id" {
  description = "AWS account ID to assume for deploying OpenVPN"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for OpenVPN. Leave empty to use first public subnet from VPC state."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID. Leave empty to use VPC ID from VPC state."
  type        = string
  default     = ""
}

variable "ssh_username" {
  description = "SSH username for the OpenVPN Access Server AMI"
  type        = string
  default     = "openvpnas"
}

variable "instance_type" {
  description = "EC2 instance type for OpenVPN server"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

variable "comcast_ip" {
  description = "Admin public IP (CIDR). Leave empty to auto-detect."
  type        = string
  default     = ""
}

variable "vpc_state_bucket" {
  description = "S3 bucket containing the VPC Terraform state"
  type        = string
  default     = "mikey-com-terraformstate"
}

variable "vpc_state_key" {
  description = "S3 object key for the prod VPC Terraform state"
  type        = string
  default     = "vpc-prod"
}

variable "vpc_state_region" {
  description = "AWS region where the VPC state bucket lives"
  type        = string
  default     = "us-east-1"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for prod.foobar.support. Get from route53/prod-delegate outputs after Step 1."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the VPN A record. FQDN will be vpn.<domain_name>"
  type        = string
  default     = "prod.foobar.support"
}

variable "enable_tls_sync" {
  description = "If true, run Ansible playbook to install TLS certificate sync cronjob on the OpenVPN server after deployment"
  type        = bool
  default     = true
}

variable "tls_secret_name" {
  description = "AWS Secrets Manager secret name for TLS certificate"
  type        = string
  default     = "openvpn/prod"
}

variable "vpc_endpoint_sg_id" {
  description = "Security group ID of VPC interface endpoints. If set, allows OpenVPN to reach endpoints on port 443."
  type        = string
  default     = ""
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window in days. 0 = immediate deletion on destroy."
  type        = number
  default     = 0
}
