# OpenVPN Terraform Variables

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "ami_id" {
  description = "AMI ID for OpenVPN Access Server"
  type        = string
  default     = "ami-0e64010cd8a5abec7"
}

variable "account_id" {
  description = "AWS account ID to assume into for deploying OpenVPN"
  type        = string
  default     = "REDACTED_ACCOUNT_ID"
}

variable "subnet_id" {
  description = "Subnet ID where the OpenVPN server will be deployed (optional - will use first private subnet if not specified)"
  type        = string
  default     = ""
}


variable "ssh_username" {
  description = "SSH username for the OpenVPN Access Server AMI (commonly 'openvpnas' or 'ubuntu')"
  type        = string
  default     = "openvpnas"
}

variable "instance_type" {
  description = "EC2 instance type for OpenVPN server"
  type        = string
  default     = "t3.small"  # Recommended for OpenVPN Access Server
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

variable "comcast_ip" {
  description = "Your public IP address for restricted access (CIDR format). Leave empty to auto-detect your current IP."
  type        = string
  default     = ""  # Empty = auto-detect, or specify like "1.2.3.4/32"
}

variable "domain" {
  description = "Domain name for the VPN server (optional)"
  type        = string
  default     = ""
}

variable "create_dns_record" {
  description = "Whether to create a Route53 DNS record"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID (required if create_dns_record is true)"
  type        = string
  default     = ""
}
