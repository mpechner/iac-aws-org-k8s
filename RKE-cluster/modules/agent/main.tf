# RKE Agent Module - Main Configuration
# This module configures existing EC2 instances as RKE agent nodes using Ansible
# Note: Security groups are managed by the EC2 module, not here

# IAM role for RKE agent nodes
resource "aws_iam_role" "rke_agent" {
  name = "${var.cluster_name}-rke-agent-role"

  assume_role_policy = file("${path.module}/policies/ec2-assume-role-policy.json")

  tags = var.tags
}

# IAM instance profile
resource "aws_iam_instance_profile" "rke_agent" {
  name = "${var.cluster_name}-rke-agent-profile"
  role = aws_iam_role.rke_agent.name
}

# Create Ansible inventory file from template
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/ansible-inventory.ini.tftpl", {
    ansible_user = var.ansible_user
    ansible_ssh_private_key_file = var.ansible_ssh_private_key_file
    agent_instance_ips = var.agent_instance_ips
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
    server_endpoint = var.server_endpoint
  })
  filename = "${path.module}/ansible/rke-agent-playbook.yml"
}

# Create Ansible template files
resource "local_file" "rke_agent_config_template" {
  content = templatefile("${path.module}/templates/rke-agent-config.yml.tftpl", {
    cluster_name = var.cluster_name
    docker_version = var.docker_version
    node_name = "agent-node"
    node_ip = "{{ ansible_default_ipv4.address }}"
  })
  filename = "${path.module}/ansible/templates/rke-agent-config.yml.j2"
}

resource "local_file" "rke_agent_service_template" {
  content = templatefile("${path.module}/templates/rke-agent.service.tftpl", {
    ansible_user = var.ansible_user
  })
  filename = "${path.module}/ansible/templates/rke-agent.service.j2"
}

resource "local_file" "join_cluster_script_template" {
  content = templatefile("${path.module}/templates/join-cluster.sh.tftpl", {
    cluster_name = var.cluster_name
    node_name = "agent-node"
    node_ip = "{{ ansible_default_ipv4.address }}"
    aws_region  = var.aws_region
  })
  filename = "${path.module}/ansible/templates/join-cluster.sh.j2"
}

# Note: Ansible provisioning should be run separately after Terraform creates the infrastructure
# The agent module creates the necessary files and infrastructure, but Ansible execution
# should be handled manually or through a separate CI/CD pipeline
# 
# To run the playbooks manually after Terraform creates the instances:
# 1. Get the instance IPs from the EC2 module outputs
# 2. Run: ansible-playbook -i inventory.ini playbook.yml 

# Run Ansible playbook on the agent instances
resource "null_resource" "ansible_provision" {
  count = length(var.agent_instance_ips)
  
  depends_on = [
    local_file.ansible_inventory,
    local_file.ansible_playbook,
    local_file.rke_agent_config_template,
    local_file.rke_agent_service_template,
    local_file.join_cluster_script_template
  ]

  triggers = {
    cluster_name = var.cluster_name
    docker_version = var.docker_version
    rke_version = var.rke_version
    instance_ip = var.agent_instance_ips[count.index]
    playbook_template_hash = filesha256("${path.module}/templates/ansible-playbook.yml.tftpl")
    # Store connection info for destroy provisioner
    ssh_user = var.ansible_user
    ssh_key_file = var.ansible_ssh_private_key_file
  }

  # Upload generated Ansible files to the instance
  provisioner "file" {
    source      = "${path.module}/ansible/"
    destination = "/home/${var.ansible_user}/ansible-playbook"

    connection {
      type        = "ssh"
      user        = var.ansible_user
      private_key = file(var.ansible_ssh_private_key_file)
      host        = var.agent_instance_ips[count.index]
    }
  }

  # This will run the Ansible playbook on each agent instance using SSH
  provisioner "remote-exec" {
    inline = [
      "for i in $(seq 1 30); do if command -v ansible-playbook >/dev/null 2>&1; then break; fi; sleep 5; done",
      "sudo pip3 install --no-cache-dir --upgrade 'boto3>=1.34.0' 'botocore>=1.34.0' || true",
      "cd /home/${var.ansible_user}/ansible-playbook",
      "ls -la",
      "ansible-galaxy collection install -r requirements.yml --force || true",
      "test -f rke-agent-playbook.yml || { echo 'missing rke-agent-playbook.yml in $(pwd)'; exit 1; }",
      "ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3 ansible-playbook -i 'localhost,' -c local rke-agent-playbook.yml --extra-vars 'cluster_name=${var.cluster_name} region=${var.aws_region} ansible_user=${var.ansible_user} server_endpoint=${var.server_endpoint}'"
    ]

    connection {
      type        = "ssh"
      user        = var.ansible_user
      private_key = file(var.ansible_ssh_private_key_file)
      host        = var.agent_instance_ips[count.index]
    }
  }

  # Cleanup: Uninstall RKE2 when destroying
  provisioner "remote-exec" {
    when = destroy
    
    inline = [
      "echo 'Uninstalling RKE2 agent...'",
      "sudo systemctl stop rke2-agent 2>/dev/null || true",
      "sudo /usr/local/bin/rke2-agent-uninstall.sh 2>/dev/null || true",
      "echo 'RKE2 agent uninstalled'"
    ]

    connection {
      type        = "ssh"
      user        = self.triggers.ssh_user
      private_key = file(self.triggers.ssh_key_file)
      host        = self.triggers.instance_ip
    }
  }

  # Health check: Verify RKE2 agent service is enabled (will join when servers are ready)
  provisioner "remote-exec" {
    inline = [
      "echo 'Verifying RKE2 agent service is enabled...'",
      "sudo systemctl is-enabled rke2-agent || { echo 'RKE2 agent service not enabled'; exit 1; }",
      "echo 'Service is enabled. It will auto-restart and join the cluster once servers are ready.'",
      "echo 'Current status:'",
      "sudo systemctl status rke2-agent --no-pager --lines=5 || true",
      "echo 'Agent node provisioning complete'"
    ]

    connection {
      type        = "ssh"
      user        = var.ansible_user
      private_key = file(var.ansible_ssh_private_key_file)
      host        = var.agent_instance_ips[count.index]
    }
  }
} 