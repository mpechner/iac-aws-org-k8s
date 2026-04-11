# ------------------------------------------------------------------------------
# IRSA — IAM Roles for Service Accounts
#
# All roles trust the EKS OIDC provider created in main.tf.
# Each trust policy is scoped to a specific namespace/service account so only
# that pod can call sts:AssumeRoleWithWebIdentity.
# ------------------------------------------------------------------------------

# Reusable trust policy — one per namespace/service-account pair
data "aws_iam_policy_document" "irsa_assume" {
  for_each = {
    "karpenter/karpenter"               = { ns = "karpenter",     sa = "karpenter" }
    "external-dns/external-dns"         = { ns = "external-dns",  sa = "external-dns" }
    "cert-manager/cert-manager"         = { ns = "cert-manager",  sa = "cert-manager" }
    "traefik/traefik"                   = { ns = "traefik",       sa = "traefik" }
    "keda/keda-operator"                = { ns = "keda",          sa = "keda-operator" }
    "kube-system/aws-load-balancer-controller" = { ns = "kube-system", sa = "aws-load-balancer-controller" }
    "openvpn-certs/openvpn-cert-publisher"  = { ns = "openvpn-certs", sa = "openvpn-cert-publisher" }
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

# ── Karpenter Controller ──────────────────────────────────────────────────────

resource "aws_iam_role" "irsa_karpenter" {
  name               = "${var.cluster_name}-irsa-karpenter"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["karpenter/karpenter"].json
}

resource "aws_iam_role_policy" "irsa_karpenter" {
  name = "${var.cluster_name}-karpenter-policy"
  role = aws_iam_role.irsa_karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2NodeProvisioning"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory",
        ]
        Resource = "*"
      },
      {
        Sid      = "PassNodeRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = data.terraform_remote_state.iam.outputs.karpenter_node_role_arn
      },
      {
        Sid    = "InterruptionQueue"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
        Resource = data.terraform_remote_state.iam.outputs.karpenter_interruption_queue_arn
      },
      {
        Sid      = "SpotPricing"
        Effect   = "Allow"
        Action   = "pricing:GetProducts"
        Resource = "*"
      },
      {
        Sid    = "AMILookup"
        Effect = "Allow"
        Action = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.region}::parameter/aws/service/eks/optimized-ami/*"
      },
      {
        Sid      = "EKSClusterAccess"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = "arn:aws:eks:${var.region}:${var.account_id}:cluster/${var.cluster_name}"
      },
    ]
  })
}

# ── External-DNS ──────────────────────────────────────────────────────────────

resource "aws_iam_role" "irsa_external_dns" {
  name               = "${var.cluster_name}-irsa-external-dns"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["external-dns/external-dns"].json
}

resource "aws_iam_role_policy" "irsa_external_dns" {
  name = "${var.cluster_name}-external-dns-policy"
  role = aws_iam_role.irsa_external_dns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
        Resource = "*"
      },
    ]
  })
}

# ── Cert-Manager ──────────────────────────────────────────────────────────────

resource "aws_iam_role" "irsa_cert_manager" {
  name               = "${var.cluster_name}-irsa-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["cert-manager/cert-manager"].json
}

resource "aws_iam_role_policy" "irsa_cert_manager" {
  name = "${var.cluster_name}-cert-manager-policy"
  role = aws_iam_role.irsa_cert_manager.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "route53:GetChange"
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect   = "Allow"
        Action   = "route53:ListHostedZonesByName"
        Resource = "*"
      },
    ]
  })
}

# ── Traefik ───────────────────────────────────────────────────────────────────

resource "aws_iam_role" "irsa_traefik" {
  name               = "${var.cluster_name}-irsa-traefik"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["traefik/traefik"].json
}

# ── AWS Load Balancer Controller ─────────────────────────────────────────────

resource "aws_iam_role" "irsa_aws_lbc" {
  name               = "${var.cluster_name}-irsa-aws-lbc"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["kube-system/aws-load-balancer-controller"].json
}

data "aws_iam_policy_document" "irsa_aws_lbc" {
  statement {
    effect  = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones", "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs", "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags", "ec2:GetCoipPoolUsage", "ec2:DescribeCoipPools",
      "ec2:GetSecurityGroupsForVpc",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "cognito-idp:DescribeUserPoolClient", "acm:ListCertificates",
      "acm:DescribeCertificate", "iam:ListServerCertificates",
      "iam:GetServerCertificate", "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource", "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL", "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource", "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL", "shield:GetSubscriptionState",
      "shield:DescribeProtection", "shield:CreateProtection",
      "shield:DeleteProtection",
    ]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateSecurityGroup"]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["true"]
    }
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }
  statement {
    effect = "Allow"
    actions = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
    ]
    resources = ["*"]
    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }
  statement {
    effect  = "Allow"
    actions = ["elasticloadbalancing:AddTags"]
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "elasticloadbalancing:CreateAction"
      values   = ["CreateTargetGroup", "CreateLoadBalancer"]
    }
    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
      values   = ["false"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
    resources = ["arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:SetWebAcl", "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "irsa_aws_lbc" {
  name   = "${var.cluster_name}-aws-lbc-policy"
  role   = aws_iam_role.irsa_aws_lbc.id
  policy = data.aws_iam_policy_document.irsa_aws_lbc.json
}

# ── KEDA ──────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "irsa_keda" {
  name               = "${var.cluster_name}-irsa-keda"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["keda/keda-operator"].json
}

resource "aws_iam_role_policy" "irsa_keda" {
  name = "${var.cluster_name}-keda-policy"
  role = aws_iam_role.irsa_keda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ListQueues",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
        ]
        Resource = "*"
      },
    ]
  })
}

# ── OpenVPN cert publisher ────────────────────────────────────────────────────
# Allows the CronJob to write the issued TLS cert into Secrets Manager.

resource "aws_iam_role" "irsa_openvpn_cert_publisher" {
  name               = "${var.cluster_name}-irsa-openvpn-cert-publisher"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume["openvpn-certs/openvpn-cert-publisher"].json
}

resource "aws_iam_role_policy" "irsa_openvpn_cert_publisher" {
  name = "${var.cluster_name}-openvpn-cert-publisher-policy"
  role = aws_iam_role.irsa_openvpn_cert_publisher.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerPut"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:openvpn/*"
      },
    ]
  })
}
