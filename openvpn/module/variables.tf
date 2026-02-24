# OpenVPN Module Variables

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the security group and instance"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the OpenVPN server will be deployed"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for OpenVPN Access Server"
  type        = string
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

variable "admin_cidr" {
  description = "CIDR allowed for SSH and admin web UI (e.g. your public IP/32)"
  type        = string
}

variable "key_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
}

variable "ssh_username" {
  description = "SSH username for the OpenVPN Access Server AMI"
  type        = string
  default     = "openvpnas"
}

variable "tags" {
  description = "Optional tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain. Leave empty to skip creating the VPN A record."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the VPN A record; hostname is always 'vpn'. FQDN will be vpn.<domain_name> (e.g. dev.foobar.support). Required when route53_zone_id is set."
  type        = string
  default     = ""
}
