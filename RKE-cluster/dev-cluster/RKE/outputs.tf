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
    To configure kubectl access, run from repo root:

    ./scripts/setup-k9s.sh ${element(data.terraform_remote_state.ec2.outputs.server_instance_private_ips, 0)}

    Or from this directory:

    ../../../scripts/setup-k9s.sh ${element(data.terraform_remote_state.ec2.outputs.server_instance_private_ips, 0)}

    The script creates/refreshes the "dev-rke2" context in ~/.kube/config. The rke-apps terraform stack pins that context name in its providers, so terraform apply works regardless of your kubectl current-context — but the dev-rke2 context must exist in your kubeconfig, which is what this script ensures.

    Then (for your own shell only — the rke-apps terraform stack does not depend on current-context):
    kubectl config use-context dev-rke2
    kubectl get nodes
  EOT
}
