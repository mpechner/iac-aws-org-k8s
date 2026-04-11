# ------------------------------------------------------------------------------
# OIDC Provider
# Created here using the cluster resource directly — no remote state needed.
# Outputs oidc_arn and oidc_issuer for 3-karpenter to consume.
# ------------------------------------------------------------------------------

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}

locals {
  oidc_issuer = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  oidc_arn    = aws_iam_openid_connect_provider.eks.arn
}

# Reusable trust policy for vpc-cni and ebs-csi service accounts
data "aws_iam_policy_document" "irsa_assume" {
  for_each = {
    "kube-system/aws-node"              = { ns = "kube-system", sa = "aws-node" }
    "kube-system/ebs-csi-controller-sa" = { ns = "kube-system", sa = "ebs-csi-controller-sa" }
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${each.value.ns}:${each.value.sa}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# ── VPC CNI ───────────────────────────────────────────────────────────────────

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_iam_role" "irsa_vpc_cni" {
  name               = "${var.cluster_name}-irsa-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["kube-system/aws-node"].json
}

resource "aws_iam_role_policy_attachment" "irsa_vpc_cni" {
  role       = aws_iam_role.irsa_vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version
  service_account_role_arn    = aws_iam_role.irsa_vpc_cni.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  timeouts {
    create = "25m"
    update = "25m"
  }
}

# ── EBS CSI Driver ────────────────────────────────────────────────────────────

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_iam_role" "irsa_ebs_csi" {
  name               = "${var.cluster_name}-irsa-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["kube-system/ebs-csi-controller-sa"].json
}

resource "aws_iam_role_policy_attachment" "irsa_ebs_csi" {
  role       = aws_iam_role.irsa_ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn    = aws_iam_role.irsa_ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  timeouts {
    create = "25m"
    update = "25m"
  }
}
