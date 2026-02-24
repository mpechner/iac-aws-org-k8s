# OpenVPN dev environment variables

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "ami_id" {
  description = "AMI ID for OpenVPN Access Server"
  type        = string
  default     = "ami-0e64010cd8a5abec7"
}

variable "account_id" {
  description = "AWS account ID to assume for deploying OpenVPN"
  type        = string
  default     = "REDACTED_ACCOUNT_ID"
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
  description = "S3 object key for the VPC Terraform state"
  type        = string
  default     = "Network"
}

variable "vpc_state_region" {
  description = "AWS region where the VPC state bucket lives"
  type        = string
  default     = "us-east-1"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain (e.g. dev.foobar.support). Leave empty to skip creating the VPN A record."
  type        = string
  default     = "Z06437531SIUA7T3WCKTM"
}

variable "domain_name" {
  description = "Domain name for the VPN A record; hostname is always 'vpn'. FQDN will be vpn.<domain_name> (e.g. vpn.dev.foobar.support)"
  type        = string
  default     = "dev.foobar.support"
}
