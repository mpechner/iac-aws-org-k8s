
variable "ansible_repo" {
  type    = string
  default = "https://github.com/your-org/your-ansible-repo.git"
}

variable "ansible_playbook" {
  type    = string
  default = "playbook.yml"
}

variable ec2_ssh_key {
    type = string
}

variable "subnet_ids" {
  type    = list(string)
  description = "subnet id names"
}

variable "agent_hostnames" {
  type    = list(string)
}
variable agent_ami {
    type = string
}

variable agent_instance_type {
    type = string
}

variable server_hostnames {
    type = list(string)
}
variable server_ami {
    type = string
}

variable server_instance_type {
    type = string
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for security group"
  default     = ""
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR to allow inbound access"
  default     = ""
}

variable "instance_profile_name" {
  type        = string
  description = "Existing IAM instance profile name to attach to instances. If empty, a new one is created."
  default     = ""
}

variable "create_ecr_pull_policy" {
  type        = bool
  description = "When creating a role, also attach a minimal ECR pull inline policy"
  default     = true
}