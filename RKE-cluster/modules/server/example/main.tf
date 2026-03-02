# Example usage of the RKE Server Module

# Configure AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Data sources for existing infrastructure
data "aws_vpc" "main" {
  tags = {
    Name = "main-vpc"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    Type = "private"
  }
}

data "aws_key_pair" "main" {
  key_name = "my-ssh-key"
}

# RKE Server Module
module "rke_servers" {
  source = "../"

  # Required variables
  cluster_name = "my-rke-cluster"
  vpc_id       = data.aws_vpc.main.id
  subnet_ids   = data.aws_subnets.private.ids
  key_name     = data.aws_key_pair.main.key_name

  # Optional variables with custom values
  server_count = 3

  ssh_cidr_blocks = [
    "10.0.0.0/8",
    "192.168.1.0/24"
  ]

  cluster_cidr_blocks = [
    "10.0.0.0/8"
  ]

  docker_version     = "20.10"
  rke_version        = "v1.4.0"
  kubernetes_version = "v1.24.10-rke2r1"

  etcd_backup_enabled   = true
  etcd_backup_retention = 7

  network_plugin           = "flannel"
  service_cluster_ip_range = "10.43.0.0/16"
  cluster_dns_service      = "10.43.0.10"

  pod_security_policy = false
  audit_log_enabled   = true

  ansible_user                 = "ec2-user"
  ansible_ssh_private_key_file = "~/.ssh/my-key.pem"

  aws_region = "us-west-2"

  tags = {
    Environment = "production"
    Project     = "rke-cluster"
    Owner       = "devops-team"
    ManagedBy   = "terraform"
  }
}

# Outputs
output "server_security_group_id" {
  description = "Security group ID for RKE server nodes"
  value       = module.rke_servers.security_group_id
}

output "server_iam_role_arn" {
  description = "IAM role ARN for RKE server nodes"
  value       = module.rke_servers.iam_role_arn
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file"
  value       = module.rke_servers.kubeconfig_path
} 