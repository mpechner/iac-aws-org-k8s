# RKE Server Module Variables

variable "cluster_name" {
  description = "Name of the RKE cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the RKE server nodes are located"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs where RKE server nodes are located"
  type        = list(string)
}

variable "server_count" {
  description = "Number of RKE server nodes to create"
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "EC2 instance type for RKE server nodes"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the SSH key pair to use for RKE server nodes"
  type        = string
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to RKE server nodes"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_cidr_blocks" {
  description = "CIDR blocks for cluster internal communication"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "associate_public_ip" {
  description = "Whether to associate public IP addresses with RKE server nodes"
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
  description = "Docker version to install on RKE server nodes"
  type        = string
  default     = "20.10"
}

variable "rke_version" {
  description = "RKE version to use for server configuration"
  type        = string
  default     = "v1.4.0"
}

variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "v1.24.10-rke2r1"
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

variable "etcd_backup_enabled" {
  description = "Whether to enable etcd backup"
  type        = bool
  default     = true
}

variable "etcd_backup_retention" {
  description = "Number of etcd backups to retain"
  type        = number
  default     = 5
}

variable "network_plugin" {
  description = "Network plugin to use (flannel, calico, canal)"
  type        = string
  default     = "flannel"
}

variable "service_cluster_ip_range" {
  description = "Kubernetes service cluster IP range"
  type        = string
  default     = "10.43.0.0/16"
}

variable "cluster_dns_service" {
  description = "Kubernetes cluster DNS service IP"
  type        = string
  default     = "10.43.0.10"
}

variable "pod_security_policy" {
  description = "Whether to enable pod security policy"
  type        = bool
  default     = false
}

variable "audit_log_enabled" {
  description = "Whether to enable audit logging"
  type        = bool
  default     = false
}

variable "audit_log_max_age" {
  description = "Maximum age of audit log files in days"
  type        = number
  default     = 30
}

variable "audit_log_max_backup" {
  description = "Maximum number of audit log backup files"
  type        = number
  default     = 10
}

variable "audit_log_max_size" {
  description = "Maximum size of audit log files in MB"
  type        = number
  default     = 100
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

variable "etcd_backup_bucket" {
  description = "S3 bucket name for etcd backups"
  type        = string
  default     = ""
}

variable "server_instance_ips" {
  description = "List of server instance IP addresses for Ansible execution"
  type        = list(string)
  default     = []
}

variable "rke2_kubectl_path" {
  description = "Full path to kubectl binary installed by RKE2"
  type        = string
  default     = "/var/lib/rancher/rke2/bin/kubectl"
} 