# RKE Agent Module Variables

variable "cluster_name" {
  description = "Name of the RKE cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the RKE agent nodes will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs where RKE agent nodes will be deployed"
  type        = list(string)
}

variable "agent_count" {
  description = "Number of RKE agent nodes to create"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type for RKE agent nodes"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the SSH key pair to use for RKE agent nodes"
  type        = string
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to RKE agent nodes"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_cidr_blocks" {
  description = "CIDR blocks for cluster internal communication"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "associate_public_ip" {
  description = "Whether to associate public IP addresses with RKE agent nodes"
  type        = bool
  default     = false
}

variable "target_group_arns" {
  description = "List of target group ARNs to attach to the Auto Scaling Group"
  type        = list(string)
  default     = []
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "docker_version" {
  description = "Docker version to install on RKE agent nodes"
  type        = string
  default     = "20.10"
}

variable "rke_version" {
  description = "RKE version to use for agent configuration"
  type        = string
  default     = "v1.4.0"
}

variable "ansible_user" {
  description = "Ansible user to connect to the instances"
  type        = string
  default     = "ec2-user"
}

variable "ansible_ssh_private_key_file" {
  description = "Path to the SSH private key file for Ansible"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ansible_repo" {
  description = "Git repository URL for Ansible playbooks"
  type        = string
  default     = "https://github.com/your-org/your-ansible-repo.git"
}

variable "ansible_playbook" {
  description = "Ansible playbook file name"
  type        = string
  default     = "playbook.yml"
}

variable "enable_irsa" {
  description = "Whether to enable IRSA (IAM Roles for Service Accounts)"
  type        = bool
  default     = false
}

variable "oidc_provider_id" {
  description = "OIDC Provider ID for IRSA"
  type        = string
  default     = ""
}

variable "app_s3_bucket" {
  description = "S3 bucket name for application data"
  type        = string
  default     = ""
} 