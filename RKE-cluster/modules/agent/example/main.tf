# Example usage of the RKE Agent Module

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

# RKE Agent Module
module "rke_agents" {
  source = "../"

  # Required variables
  cluster_name = "my-rke-cluster"
  vpc_id       = data.aws_vpc.main.id
  subnet_ids   = data.aws_subnets.private.ids
  key_name     = data.aws_key_pair.main.key_name

  # Optional variables with custom values
  agent_count   = 3
  instance_type = "t3.medium"

  ssh_cidr_blocks = [
    "10.0.0.0/8",
    "192.168.1.0/24"
  ]

  cluster_cidr_blocks = [
    "10.0.0.0/8"
  ]

  associate_public_ip = false

  docker_version = "20.10"
  rke_version    = "v1.4.0"

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
output "agent_security_group_id" {
  description = "Security group ID for RKE agent nodes"
  value       = module.rke_agents.security_group_id
}

output "agent_autoscaling_group_name" {
  description = "Auto Scaling Group name for RKE agent nodes"
  value       = module.rke_agents.autoscaling_group_name
}

output "agent_iam_role_arn" {
  description = "IAM role ARN for RKE agent nodes"
  value       = module.rke_agents.iam_role_arn
} 