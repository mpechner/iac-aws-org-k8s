
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