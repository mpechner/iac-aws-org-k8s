# ------------------------------------------------------------------------------
# Remote state — pull outputs from 1-iam and 2-cluster
# ------------------------------------------------------------------------------

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = var.iam_state_bucket
    key    = var.iam_state_key
    region = var.iam_state_region
  }
}

data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket = var.cluster_state_bucket
    key    = var.cluster_state_key
    region = var.cluster_state_region
  }
}

locals {
  oidc_issuer = data.terraform_remote_state.cluster.outputs.oidc_issuer
  oidc_arn    = data.terraform_remote_state.cluster.outputs.oidc_arn
}

# ------------------------------------------------------------------------------
# EKS Access Entry for Karpenter nodes
# Modern replacement for aws-auth ConfigMap. Grants EC2 nodes launched by
# Karpenter the ability to register with the cluster.
# ------------------------------------------------------------------------------

resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = var.cluster_name
  principal_arn = data.terraform_remote_state.iam.outputs.karpenter_node_role_arn
  type          = "EC2_LINUX"
}

# ------------------------------------------------------------------------------
# Karpenter Namespace
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "karpenter_namespace" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: karpenter
  YAML
}

# ------------------------------------------------------------------------------
# Karpenter Helm Release
# Pinned to bootstrap nodes via tolerations + nodeSelector so it never
# accidentally schedules on Karpenter-managed nodes during restarts.
# ------------------------------------------------------------------------------

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  namespace  = "karpenter"

  wait    = true
  timeout = 300

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.interruptionQueue"
    value = data.terraform_remote_state.iam.outputs.karpenter_interruption_queue_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.irsa_karpenter.arn
  }

  # Pin Karpenter to the bootstrap node group
  set {
    name  = "nodeSelector.node\\.kubernetes\\.io/purpose"
    value = "karpenter"
  }

  set {
    name  = "tolerations[0].key"
    value = "CriticalAddonsOnly"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  depends_on = [
    aws_iam_role.irsa_karpenter,
    aws_eks_access_entry.karpenter_nodes,
    kubectl_manifest.karpenter_namespace,
  ]
}
