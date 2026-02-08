output "rke_ssh_secret_name" {
  description = "Name of the Secrets Manager secret storing the RKE SSH keypair"
  value       = aws_secretsmanager_secret.rke_ssh_keypair.name
}

output "rke_ssh_key_name" {
  description = "EC2 key pair name used for RKE nodes"
  value       = aws_key_pair.rke_ssh.key_name
}

output "server_instance_private_ips" {
  description = "List of server instance private IPs from the EC2 module"
  value       = module.rke-nodes.server_instance_private_ips
}

output "agent_instance_private_ips" {
  description = "List of agent instance private IPs from the EC2 module"
  value       = module.rke-nodes.agent_instance_private_ips
}

output "instances_ready" {
  description = "Status message indicating all instances are ready"
  value       = module.rke-nodes.all_instances_ready
}

output "next_steps" {
  description = "Instructions for next steps"
  value       = <<-EOT
    ✓ All EC2 instances are ready!
    
    Next steps:
    1. Copy the RKE SSH key from Secrets Manager:
       Secret name: ${aws_secretsmanager_secret.rke_ssh_keypair.name}
       Save private key to: ~/.ssh/rke-key
       Set permissions: chmod 600 ~/.ssh/rke-key
    
    2. Make sure you're connected to the VPN
    
    3. Deploy RKE cluster:
       cd ../rke
       terraform apply
  EOT
}

