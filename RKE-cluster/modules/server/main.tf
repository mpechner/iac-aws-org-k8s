# RKE Server Module - Main Configuration
# This module configures existing EC2 instances as RKE server (control plane) nodes using Ansible
# Note: Security groups are managed by the EC2 module, not here

# IAM role for RKE server nodes
resource "aws_iam_role" "rke_server" {
  name = "${var.cluster_name}-rke-server-role"

  assume_role_policy = file("${path.module}/policies/ec2-assume-role-policy.json")

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
    server_instance_ips = var.server_instance_ips
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
    server_instance_ips = var.server_instance_ips
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
    network_plugin = var.network_plugin
    service_cluster_ip_range = var.service_cluster_ip_range
    pod_security_policy = var.pod_security_policy
    audit_log_enabled = var.audit_log_enabled
    audit_log_max_age = var.audit_log_max_age
    audit_log_max_backup = var.audit_log_max_backup
    audit_log_max_size = var.audit_log_max_size
    cluster_dns_service = var.cluster_dns_service
    node_ip = "{{ ansible_default_ipv4.address }}"
    ansible_user = var.ansible_user
    ansible_ssh_private_key_file = var.ansible_ssh_private_key_file
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
    ansible_user = var.ansible_user
    aws_region  = var.aws_region
  })
  filename = "${path.module}/ansible/templates/init-cluster.sh.j2"
}

# Note: Ansible provisioning should be run separately after Terraform creates the infrastructure
# The server module creates the necessary files and infrastructure, but Ansible execution
# should be handled manually or through a separate CI/CD pipeline

# Run Ansible playbook on the server instances
resource "null_resource" "ansible_provision" {
  count = length(var.server_instance_ips)
  
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
    instance_ip = var.server_instance_ips[count.index]
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
      host        = var.server_instance_ips[count.index]
    }
  }

  # This will run the Ansible playbook on each server instance using SSH
  provisioner "remote-exec" {
    inline = [
      "for i in $(seq 1 30); do if command -v ansible-playbook >/dev/null 2>&1; then break; fi; sleep 5; done",
      "sudo pip3 install --no-cache-dir --upgrade 'boto3>=1.34.0' 'botocore>=1.34.0' || true",
      "cd /home/${var.ansible_user}/ansible-playbook",
      "ls -la",
      "ansible-galaxy collection install -r requirements.yml --force || true",
      "test -f rke-server-playbook.yml || { echo 'missing rke-server-playbook.yml in $(pwd)'; exit 1; }",
      "ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3 ansible-playbook -i 'localhost,' -c local rke-server-playbook.yml --extra-vars 'cluster_name=${var.cluster_name} region=${var.aws_region} ansible_user=${var.ansible_user}'"
    ]

    connection {
      type        = "ssh"
      user        = var.ansible_user
      private_key = file(var.ansible_ssh_private_key_file)
      host        = var.server_instance_ips[count.index]
    }
  }

  # Cleanup: Uninstall RKE2 when destroying
  provisioner "remote-exec" {
    when = destroy
    
    inline = [
      "echo 'Uninstalling RKE2 server...'",
      "sudo systemctl stop rke2-server 2>/dev/null || true",
      "sudo /usr/local/bin/rke2-uninstall.sh 2>/dev/null || true",
      "echo 'RKE2 server uninstalled'"
    ]

    connection {
      type        = "ssh"
      user        = self.triggers.ssh_user
      private_key = file(self.triggers.ssh_key_file)
      host        = self.triggers.instance_ip
    }
  }

  # Health check: Wait for Kubernetes API server to be ready (only on first server)
  provisioner "remote-exec" {
    inline = count.index == 0 ? [
      "echo 'Waiting for Kubernetes API server to be ready...'",
      "export PATH=$PATH:/var/lib/rancher/rke2/bin",
      "for i in $(seq 1 60); do",
      "  if sudo ${var.rke2_kubectl_path} --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes &>/dev/null; then",
      "    echo 'API server is ready'",
      "    break",
      "  fi",
      "  echo \"Waiting for API server... attempt $i/60\"",
      "  sleep 5",
      "done",
      "sudo ${var.rke2_kubectl_path} --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes || { echo 'API server not ready after 5 minutes'; exit 1; }"
    ] : [
      "echo 'Additional server - waiting for first server API to be available...'",
      "for i in $(seq 1 60); do",
      "  if nc -z -w5 ${var.server_instance_ips[0]} 9345 2>/dev/null; then",
      "    echo 'First server is reachable on port 9345'",
      "    break",
      "  fi",
      "  echo \"Waiting for first server... attempt $i/60\"",
      "  sleep 5",
      "done",
      "nc -z -w5 ${var.server_instance_ips[0]} 9345 || { echo 'First server not reachable after 5 minutes'; exit 1; }",
      "echo 'Verifying RKE2 server service is enabled and will join cluster...'",
      "sudo systemctl is-enabled rke2-server || { echo 'RKE2 server service not enabled'; exit 1; }",
      "echo 'Service is enabled. It will auto-restart and join the cluster once first server is ready.'",
      "echo 'Current status:'",
      "sudo systemctl status rke2-server --no-pager --lines=5 || true"
    ]

    connection {
      type        = "ssh"
      user        = var.ansible_user
      private_key = file(var.ansible_ssh_private_key_file)
      host        = var.server_instance_ips[count.index]
    }
  }

  # Health check: Wait for CNI to be deployed (only on first server)
  provisioner "remote-exec" {
    inline = count.index == 0 ? [
      "echo 'Waiting for CNI (Canal) pods to be running...'",
      "sudo ${var.rke2_kubectl_path} --kubeconfig=/etc/rancher/rke2/rke2.yaml wait --for=condition=Ready pod -l k8s-app=canal -n kube-system --timeout=300s || echo 'Warning: CNI pods not ready after 5 minutes'",
      "echo 'Checking CNI pod status:'",
      "sudo ${var.rke2_kubectl_path} --kubeconfig=/etc/rancher/rke2/rke2.yaml get pods -n kube-system -l k8s-app=canal"
    ] : ["echo 'Skipping CNI check on additional server nodes'"]

    connection {
      type        = "ssh"
      user        = var.ansible_user
      private_key = file(var.ansible_ssh_private_key_file)
      host        = var.server_instance_ips[count.index]
    }
  }

  # Health check: Wait for control plane node to be Ready (only on first server)
  provisioner "remote-exec" {
    inline = count.index == 0 ? [
      "echo 'Waiting for control plane node to be Ready...'",
      "sudo ${var.rke2_kubectl_path} --kubeconfig=/etc/rancher/rke2/rke2.yaml wait --for=condition=Ready node --selector=node-role.kubernetes.io/control-plane=true --timeout=120s || echo 'Warning: Control plane node not ready after 2 minutes'",
      "echo 'Final cluster status:'",
      "sudo ${var.rke2_kubectl_path} --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes",
      "echo 'RKE2 server initialization complete'"
    ] : [
      "echo 'RKE2 server node provisioning complete'"
    ]

    connection {
      type        = "ssh"
      user        = var.ansible_user
      private_key = file(var.ansible_ssh_private_key_file)
      host        = var.server_instance_ips[count.index]
    }
  }
} 