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


