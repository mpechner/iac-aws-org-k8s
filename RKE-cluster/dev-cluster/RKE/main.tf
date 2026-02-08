data "terraform_remote_state" "ec2" {
  backend = "s3"
  config = {
    bucket         = "mikey-com-terraformstate"
    use_lockfile   = true
    key            = "RKE-cluster_dev/ec2"
    region         = "us-east-1"
  }
}

resource "random_password" "rke2_token" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "rke2_token" {
  name = "${local.cluster_name}-rke2-token"
}

resource "aws_secretsmanager_secret_version" "rke2_token" {
  secret_id     = aws_secretsmanager_secret.rke2_token.id
  secret_string = random_password.rke2_token.result
}

module "rke-server"{
  source= "../../modules/server"
  cluster_name = local.cluster_name
  vpc_id = data.aws_vpc.current.id
  subnet_ids = data.aws_subnets.node_subnets.ids
  key_name = data.terraform_remote_state.ec2.outputs.rke_ssh_key_name
  aws_region = var.aws_region
  server_instance_ips = data.terraform_remote_state.ec2.outputs.server_instance_private_ips
  ansible_user = "ubuntu"
  ansible_ssh_private_key_file = "~/.ssh/rke-key"
  
  # Enable etcd backups to S3
  etcd_backup_enabled = true
  etcd_backup_bucket  = "mikey-dev-rke-etcd-backups"
  
  depends_on = [aws_secretsmanager_secret_version.rke2_token]

}

module "rke-agent" {
  source = "../../modules/agent"
  cluster_name = local.cluster_name
  vpc_id = data.aws_vpc.current.id
  subnet_ids = data.aws_subnets.node_subnets.ids
  key_name = data.terraform_remote_state.ec2.outputs.rke_ssh_key_name
  aws_region = var.aws_region
  agent_instance_ips = data.terraform_remote_state.ec2.outputs.agent_instance_private_ips
  ansible_user = "ubuntu"
  ansible_ssh_private_key_file = "~/.ssh/rke-key"
  server_endpoint = element(data.terraform_remote_state.ec2.outputs.server_instance_private_ips, 0)
  depends_on = [aws_secretsmanager_secret_version.rke2_token, module.rke-server]

}

# Final health check: Verify all RKE2 services are running
resource "null_resource" "cluster_ready_check" {
  depends_on = [module.rke-server, module.rke-agent]

  triggers = {
    server_ips = join(",", data.terraform_remote_state.ec2.outputs.server_instance_private_ips)
    agent_ips  = join(",", data.terraform_remote_state.ec2.outputs.agent_instance_private_ips)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "========================================"
      echo "Verifying RKE2 services on all nodes..."
      echo "========================================"
      
      # Check all server nodes
      %{for ip in data.terraform_remote_state.ec2.outputs.server_instance_private_ips~}
      echo "Checking rke2-server service on ${ip}..."
      ssh -o StrictHostKeyChecking=no -i ~/.ssh/rke-key ubuntu@${ip} '
        if ! sudo systemctl is-active rke2-server >/dev/null 2>&1; then
          echo "ERROR: rke2-server service is not active on ${ip}"
          sudo systemctl status rke2-server --no-pager
          exit 1
        fi
        echo "✓ rke2-server is active on ${ip}"
      ' || exit 1
      %{endfor~}
      
      # Check all agent nodes
      %{for ip in data.terraform_remote_state.ec2.outputs.agent_instance_private_ips~}
      echo "Checking rke2-agent service on ${ip}..."
      ssh -o StrictHostKeyChecking=no -i ~/.ssh/rke-key ubuntu@${ip} '
        if ! sudo systemctl is-active rke2-agent >/dev/null 2>&1; then
          echo "ERROR: rke2-agent service is not active on ${ip}"
          sudo systemctl status rke2-agent --no-pager
          exit 1
        fi
        echo "✓ rke2-agent is active on ${ip}"
      ' || exit 1
      %{endfor~}
      
      echo ""
      echo "========================================"
      echo "All RKE2 services are running!"
      echo "========================================"
      
      # Now verify cluster node readiness
      echo ""
      echo "Verifying cluster node status..."
      ssh -o StrictHostKeyChecking=no -i ~/.ssh/rke-key ubuntu@${element(data.terraform_remote_state.ec2.outputs.server_instance_private_ips, 0)} '
        EXPECTED_COUNT=$((${length(data.terraform_remote_state.ec2.outputs.server_instance_private_ips)} + ${length(data.terraform_remote_state.ec2.outputs.agent_instance_private_ips)}))
        
        for i in $(seq 1 30); do
          READY_COUNT=$(sudo kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
          
          if [ "$READY_COUNT" -eq "$EXPECTED_COUNT" ]; then
            echo "✓ All $EXPECTED_COUNT nodes are Ready!"
            echo ""
            sudo kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes
            exit 0
          fi
          
          echo "Waiting for nodes to be Ready: $READY_COUNT/$EXPECTED_COUNT (attempt $i/30)"
          sleep 10
        done
        
        echo "WARNING: Not all nodes are Ready yet, but RKE2 services are running"
        echo "Current node status:"
        sudo kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes
        exit 0
      ' || exit 1
      
      echo ""
      echo "✓ RKE cluster deployment complete!"
    EOT
  }
}