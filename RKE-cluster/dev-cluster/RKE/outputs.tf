output "cluster_ready" {
  description = "Indicates the RKE cluster is fully operational with all nodes Ready"
  value       = "RKE2 cluster is ready! All ${length(data.terraform_remote_state.ec2.outputs.server_instance_private_ips) + length(data.terraform_remote_state.ec2.outputs.agent_instance_private_ips)} nodes are operational."
  depends_on  = [null_resource.cluster_ready_check]
}

output "server_ips" {
  description = "RKE server IP addresses"
  value       = data.terraform_remote_state.ec2.outputs.server_instance_private_ips
}

output "agent_ips" {
  description = "RKE agent IP addresses"
  value       = data.terraform_remote_state.ec2.outputs.agent_instance_private_ips
}

output "kubeconfig_instructions" {
  description = "Instructions for setting up kubectl access"
  value       = <<-EOT
    To configure kubectl access, run:
    
    ./scripts/setup-k9s.sh ${element(data.terraform_remote_state.ec2.outputs.server_instance_private_ips, 0)}
    
    Then verify:
    kubectl config use-context dev-rke2
    kubectl get nodes
  EOT
}
