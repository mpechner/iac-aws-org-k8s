# Patch RKE2 node providerIDs to AWS format so the AWS Load Balancer Controller can register
# instance targets. Uses only Terraform AWS and Kubernetes providers (same assume role as rest of stack;
# no scripts or AWS profile required).

data "kubernetes_nodes" "cluster" {
  count = var.patch_node_provider_ids ? 1 : 0
}

locals {
  # Map node name -> InternalIP from cluster nodes (only when patching is enabled).
  # Provider may use metadata[0].name or metadata.name, status[0].addresses or status.addresses.
  node_internal_ips = var.patch_node_provider_ids ? {
    for node in try(data.kubernetes_nodes.cluster[0].nodes, []) :
    try(node.metadata[0].name, node.metadata.name, "") => try(
      [for a in try(node.status[0].addresses, node.status.addresses, []) : a.address if a.type == "InternalIP"][0],
      null
    ) if try(node.metadata[0].name, node.metadata.name, null) != null && try(node.metadata[0].name, node.metadata.name, "") != ""
  } : {}
  # Only nodes with a resolvable InternalIP
  node_internal_ips_filtered = { for k, v in local.node_internal_ips : k => v if v != null && v != "" }
}

# Resolve EC2 instance ID (and AZ) by private IP using Terraform AWS provider (terraform-exec role).
data "aws_instances" "by_private_ip" {
  for_each = local.node_internal_ips_filtered

  filter {
    name   = "private-ip-address"
    values = [each.value]
  }
  instance_state_names = ["running"]
}

data "aws_instance" "placement" {
  for_each = {
    for name, ip in local.node_internal_ips_filtered :
    name => data.aws_instances.by_private_ip[name].ids[0]
    if length(data.aws_instances.by_private_ip[name].ids) > 0
  }

  instance_id = each.value
}

locals {
  # Node name -> AWS format providerID (aws:///az/instance-id)
  node_provider_ids = {
    for name in keys(data.aws_instance.placement) :
    name => "aws:///${data.aws_instance.placement[name].availability_zone}/${data.aws_instance.placement[name].id}"
  }
}

# Apply providerID patches via kubectl only (no AWS CLI). Terraform has already resolved
# instance IDs using the AWS provider; this step only runs kubectl.
resource "null_resource" "patch_node_provider_ids" {
  for_each = var.patch_node_provider_ids ? local.node_provider_ids : {}

  triggers = {
    node_name   = each.key
    provider_id = each.value
  }

  provisioner "local-exec" {
    command = <<-EOT
      CURRENT=$(kubectl get node ${each.key} -o jsonpath='{.spec.providerID}' 2>/dev/null || echo "")
      DESIRED="${each.value}"
      if [ "$CURRENT" = "$DESIRED" ]; then
        echo "Node ${each.key} providerID already set to $DESIRED, skipping."
      elif [ -z "$CURRENT" ]; then
        kubectl patch node ${each.key} -p "{\"spec\":{\"providerID\":\"$DESIRED\"}}"
      else
        echo "Node ${each.key} providerID already set to $CURRENT (wanted $DESIRED). Cannot change non-empty providerID; skipping."
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "true" # No-op on destroy; node may already be gone
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

# Restart AWS LB controller so it picks up the new providerIDs and registers targets.
resource "null_resource" "restart_aws_lb_controller_after_provider_id_patch" {
  count = var.patch_node_provider_ids && length(local.node_provider_ids) > 0 ? 1 : 0

  triggers = {
    node_provider_ids = jsonencode(local.node_provider_ids)
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
      kubectl rollout status deployment aws-load-balancer-controller -n kube-system --timeout=120s
    EOT
  }

  depends_on = [null_resource.patch_node_provider_ids]
}
