# RKE Server Module - Main Configuration
# This module configures existing EC2 instances as RKE server (control plane) nodes using Ansible

# Security group for RKE server nodes
resource "aws_security_group" "rke_server" {
  name_prefix = "${var.cluster_name}-rke-server-"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  # RKE required ports for control plane
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.cluster_cidr_blocks
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = var.cluster_cidr_blocks
  }

  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = var.cluster_cidr_blocks
  }

  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = var.cluster_cidr_blocks
  }

  ingress {
    from_port   = 9099
    to_port     = 9099
    protocol    = "tcp"
    cidr_blocks = var.cluster_cidr_blocks
  }

  # Additional ports for control plane
  ingress {
    from_port   = 10251
    to_port     = 10251
    protocol    = "tcp"
    cidr_blocks = var.cluster_cidr_blocks
  }

  ingress {
    from_port   = 10252
    to_port     = 10252
    protocol    = "tcp"
    cidr_blocks = var.cluster_cidr_blocks
  }

  ingress {
    from_port   = 10255
    to_port     = 10255
    protocol    = "tcp"
    cidr_blocks = var.cluster_cidr_blocks
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-rke-server-sg"
  })
}

# IAM role for RKE server nodes
resource "aws_iam_role" "rke_server" {
  name = "${var.cluster_name}-rke-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM instance profile
resource "aws_iam_instance_profile" "rke_server" {
  name = "${var.cluster_name}-rke-server-profile"
  role = aws_iam_role.rke_server.name
}

# Create Ansible inventory file from template
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/ansible-inventory.ini.tftpl", {
    ansible_user = var.ansible_user
    ansible_ssh_private_key_file = var.ansible_ssh_private_key_file
  })
  filename = "${path.module}/ansible/inventory.ini"
}

# Create Ansible playbook from template
resource "local_file" "ansible_playbook" {
  content = templatefile("${path.module}/templates/ansible-playbook.yml.tftpl", {
    cluster_name = var.cluster_name
    aws_region = var.aws_region
    ansible_user = var.ansible_user
    ansible_ssh_private_key_file = var.ansible_ssh_private_key_file
    docker_version = var.docker_version
    rke_version = var.rke_version
    kubernetes_version = var.kubernetes_version
    etcd_backup_enabled = var.etcd_backup_enabled
    etcd_backup_retention = var.etcd_backup_retention
  })
  filename = "${path.module}/ansible/rke-server-playbook.yml"
}

# Create Ansible template files
resource "local_file" "rke_server_config_template" {
  content = templatefile("${path.module}/templates/rke-server-config.yml.tftpl", {
    cluster_name = var.cluster_name
    docker_version = var.docker_version
    kubernetes_version = var.kubernetes_version
    etcd_backup_enabled = var.etcd_backup_enabled
    etcd_backup_retention = var.etcd_backup_retention
  })
  filename = "${path.module}/ansible/templates/rke-server-config.yml.j2"
}

resource "local_file" "rke_server_service_template" {
  content = templatefile("${path.module}/templates/rke-server.service.tftpl", {
    ansible_user = var.ansible_user
  })
  filename = "${path.module}/ansible/templates/rke-server.service.j2"
}

resource "local_file" "cluster_init_script_template" {
  content = templatefile("${path.module}/templates/init-cluster.sh.tftpl", {
    cluster_name = var.cluster_name
  })
  filename = "${path.module}/ansible/templates/init-cluster.sh.j2"
}

# Null resource to run Ansible playbook after instances are discovered
resource "null_resource" "ansible_provision" {
  depends_on = [
    local_file.ansible_inventory,
    local_file.ansible_playbook,
    local_file.rke_server_config_template,
    local_file.rke_server_service_template,
    local_file.cluster_init_script_template
  ]

  triggers = {
    cluster_name = var.cluster_name
    docker_version = var.docker_version
    rke_version = var.rke_version
    kubernetes_version = var.kubernetes_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      sleep 30  # Wait for instances to be ready
      ansible-playbook \
        -i ${path.module}/ansible/inventory.ini \
        ${path.module}/ansible/rke-server-playbook.yml \
        --extra-vars "cluster_name=${var.cluster_name} region=${var.aws_region}"
    EOT
  }
} 