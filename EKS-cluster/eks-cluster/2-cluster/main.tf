# Pull outputs from 1-iam and VPC
data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = var.iam_state_bucket
    key    = var.iam_state_key
    region = var.iam_state_region
  }
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.vpc_state_bucket
    key    = var.vpc_state_key
    region = var.vpc_state_region
  }
}

locals {
  # EKS nodes reuse the dev-rke-* subnets (indices 3-5 of private_subnets).
  # VPC outputs all 6 private subnets: [priv-a, priv-b, priv-c, rke-a, rke-b, rke-c]
  eks_subnet_ids = slice(data.terraform_remote_state.vpc.outputs.private_subnets, 3, 6)
}

# ------------------------------------------------------------------------------
# EKS Cluster
# ------------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = data.terraform_remote_state.iam.outputs.cluster_role_arn

  vpc_config {
    subnet_ids              = local.eks_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false # VPN required — no public API endpoint
  }

  # Secrets envelope encryption using KMS CMK from 1-iam
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = data.terraform_remote_state.iam.outputs.kms_key_arn
    }
  }

  # Ship all control plane logs to CloudWatch
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}

# Allow VPN clients to reach the EKS private API endpoint (port 443)
resource "aws_security_group_rule" "eks_api_from_vpn" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description       = "Allow VPN clients to reach EKS API"
}

# Tag EKS subnets with the cluster name for LB controller subnet discovery.
# Done here (not in VPC) so VPC stays decoupled from the cluster name.
resource "aws_ec2_tag" "eks_subnet_cluster_tag" {
  for_each    = toset(local.eks_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

# ------------------------------------------------------------------------------
# EKS Access Entry for bootstrap nodes
# Allows the bootstrap managed node group to register with the cluster.
# ------------------------------------------------------------------------------

resource "aws_eks_access_entry" "bootstrap_nodes" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.terraform_remote_state.iam.outputs.bootstrap_node_role_arn
  type          = "EC2_LINUX"
}

# Admin access entry — grants cluster-admin to the operator's IAM role (e.g. SSO)
resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ------------------------------------------------------------------------------
# Bootstrap Managed Node Group
# Hosts Karpenter controller only. Tainted so nothing else schedules here.
# ------------------------------------------------------------------------------

resource "aws_launch_template" "bootstrap_nodes" {
  name_prefix = "${var.cluster_name}-bootstrap-"

  metadata_options {
    http_tokens                 = "required" # IMDSv2 required
    http_put_response_hop_limit = 2          # nodes can reach IMDS; pods cannot
    http_endpoint               = "enabled"
  }

  # No key_name — SSM access only, no SSH
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-karpenter-bootstrap"
    }
  }
}

resource "aws_eks_node_group" "karpenter_bootstrap" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-karpenter-bootstrap"
  node_role_arn   = data.terraform_remote_state.iam.outputs.bootstrap_node_role_arn
  subnet_ids      = local.eks_subnet_ids
  instance_types = [var.bootstrap_instance_type]

  scaling_config {
    min_size     = var.bootstrap_node_count
    desired_size = var.bootstrap_node_count
    max_size     = var.bootstrap_node_count + 1  # 1 surge node during rolling update
  }

  # Roll one node at a time: cordon → drain → replace → next.
  # 33% = 1 of 3 nodes; max = desired + 1 provides one surge slot.
  update_config {
    max_unavailable_percentage = 33
  }

  # Only Karpenter pods tolerate this taint; all other workloads go to Karpenter nodes
  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  labels = {
    "node.kubernetes.io/purpose" = "karpenter"
  }

  launch_template {
    id      = aws_launch_template.bootstrap_nodes.id
    version = aws_launch_template.bootstrap_nodes.latest_version
  }

  lifecycle {
    ignore_changes = [scaling_config]
  }
}

# ------------------------------------------------------------------------------
# EKS Managed Add-ons
# coredns and kube-proxy are managed here. vpc-cni and ebs-csi are managed in
# 3-karpenter where the OIDC provider and IRSA roles exist, so they can be
# created with service_account_role_arn in a single step.
# Bootstrap nodes use the AMI's pre-installed vpc-cni until step 3 completes.
# ------------------------------------------------------------------------------

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  timeouts {
    create = "25m"
    update = "25m"
  }

  depends_on = [aws_eks_node_group.karpenter_bootstrap]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  timeouts {
    create = "25m"
    update = "25m"
  }
}
