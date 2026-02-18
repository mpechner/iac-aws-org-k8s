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
  
  # Force immediate deletion instead of 30-day recovery window
  # This allows terraform destroy/apply cycles without waiting
  recovery_window_in_days = 0
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
      
      # Give services time to become active (wait up to 5 minutes)
      echo "Waiting for all RKE2 services to become active..."
      for attempt in $(seq 1 30); do
        ALL_ACTIVE=true
        
        # Check all server nodes
        %{for ip in data.terraform_remote_state.ec2.outputs.server_instance_private_ips~}
        if ! ssh -o StrictHostKeyChecking=no -i ~/.ssh/rke-key ubuntu@${ip} 'sudo systemctl is-active rke2-server >/dev/null 2>&1'; then
          echo "Server ${ip} not active yet (attempt $attempt/30)"
          ALL_ACTIVE=false
          break
        fi
        %{endfor~}
        
        # Check all agent nodes
        if [ "$ALL_ACTIVE" = true ]; then
          %{for ip in data.terraform_remote_state.ec2.outputs.agent_instance_private_ips~}
          if ! ssh -o StrictHostKeyChecking=no -i ~/.ssh/rke-key ubuntu@${ip} 'sudo systemctl is-active rke2-agent >/dev/null 2>&1'; then
            echo "Agent ${ip} not active yet (attempt $attempt/30)"
            ALL_ACTIVE=false
            break
          fi
          %{endfor~}
        fi
        
        if [ "$ALL_ACTIVE" = true ]; then
          echo "✓ All RKE2 services are active!"
          break
        fi
        
        sleep 10
      done
      
      if [ "$ALL_ACTIVE" != true ]; then
        echo "WARNING: Not all services became active within 5 minutes"
        echo "Checking individual service status..."
        %{for ip in data.terraform_remote_state.ec2.outputs.server_instance_private_ips~}
        echo "Server ${ip}:"
        ssh -o StrictHostKeyChecking=no -i ~/.ssh/rke-key ubuntu@${ip} 'sudo systemctl status rke2-server --no-pager --lines=3'
        %{endfor~}
      fi
      
      echo ""
      echo "========================================"
      echo "Verifying cluster node readiness..."
      echo "========================================"
      
      # Verify cluster node readiness (one node can lag; wait up to 8 min for all to be Ready)
      ssh -o StrictHostKeyChecking=no -i ~/.ssh/rke-key ubuntu@${element(data.terraform_remote_state.ec2.outputs.server_instance_private_ips, 0)} '
        EXPECTED_COUNT=$((${length(data.terraform_remote_state.ec2.outputs.server_instance_private_ips)} + ${length(data.terraform_remote_state.ec2.outputs.agent_instance_private_ips)}))
        MAX_ATTEMPTS=48
        
        for i in $(seq 1 $MAX_ATTEMPTS); do
          READY_COUNT=$(sudo ${local.rke2_kubectl_path} --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
          
          if [ "$READY_COUNT" -eq "$EXPECTED_COUNT" ]; then
            echo "✓ All $EXPECTED_COUNT nodes are Ready!"
            echo ""
            sudo ${local.rke2_kubectl_path} --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes
            exit 0
          fi
          
          echo "Waiting for nodes to be Ready: $READY_COUNT/$EXPECTED_COUNT (attempt $i/$MAX_ATTEMPTS)"
          sleep 10
        done
        
        echo "ERROR: Only $READY_COUNT/$EXPECTED_COUNT nodes are Ready after 8 minutes."
        echo "Current node status:"
        sudo ${local.rke2_kubectl_path} --kubeconfig=/etc/rancher/rke2/rke2.yaml get nodes
        echo ""
        echo "SSH to any server (e.g. ${element(data.terraform_remote_state.ec2.outputs.server_instance_private_ips, 0)}) and run: kubectl get nodes -o wide"
        echo "Then check the missing/NotReady node: ssh ubuntu@<node-ip> and run: sudo systemctl status rke2-server or rke2-agent, and journalctl -u rke2-server -n 100"
        exit 1
      ' || exit 1
      
      echo ""
      echo "✓ RKE cluster deployment complete!"
    EOT
  }
}