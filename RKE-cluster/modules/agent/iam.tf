# IAM Policies for RKE Agent Nodes

# Basic EC2 permissions for agent nodes
resource "aws_iam_role_policy" "rke_agent_ec2" {
  name = "${var.cluster_name}-rke-agent-ec2-policy"
  role = aws_iam_role.rke_agent.id
  
  policy = file("${path.module}/policies/agent-ec2-policy.json")
}

# ECR permissions for pulling container images
resource "aws_iam_role_policy" "rke_agent_ecr" {
  name = "${var.cluster_name}-rke-agent-ecr-policy"
  role = aws_iam_role.rke_agent.id
  
  policy = file("${path.module}/policies/agent-ecr-policy.json")
}

# CloudWatch permissions for logging and metrics
resource "aws_iam_role_policy" "rke_agent_cloudwatch" {
  name = "${var.cluster_name}-rke-agent-cloudwatch-policy"
  role = aws_iam_role.rke_agent.id
  
  policy = file("${path.module}/policies/agent-cloudwatch-policy.json")
}

# Systems Manager permissions for node management
resource "aws_iam_role_policy" "rke_agent_ssm" {
  name = "${var.cluster_name}-rke-agent-ssm-policy"
  role = aws_iam_role.rke_agent.id
  
  policy = file("${path.module}/policies/agent-ssm-policy.json")
}

# Route53 permissions for cert-manager and external-dns
resource "aws_iam_role_policy" "rke_agent_route53" {
  name = "${var.cluster_name}-rke-agent-route53-policy"
  role = aws_iam_role.rke_agent.id
  
  policy = file("${path.module}/policies/agent-route53-policy.json")
}

# OIDC Provider for IRSA (if not already created)
resource "aws_iam_openid_connect_provider" "rke_oidc" {
  count = var.enable_irsa ? 1 : 0
  
  url = "https://oidc.eks.${var.aws_region}.amazonaws.com/id/${var.oidc_provider_id}"
  
  client_id_list = ["sts.amazonaws.com"]
  
  thumbprint_list = [
    "9e99a48a9960b14926bb7f3b02e22da2b0ab7280",
    "a031c46782e6e6c662c2c87c76da9aa62ccabd8e"
  ]
  
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-oidc-provider"
  })
}

# IRSA Role for default service accounts
resource "aws_iam_role" "default_service_account" {
  count = var.enable_irsa ? 1 : 0
  
  name = "${var.cluster_name}-default-sa-role"
  
  assume_role_policy = templatefile("${path.module}/policies/irsa-assume-role-policy.json.tftpl", {
    oidc_provider_arn = aws_iam_openid_connect_provider.rke_oidc[0].arn
    oidc_provider_url = aws_iam_openid_connect_provider.rke_oidc[0].url
    namespace = "default"
    service_account = "default-sa"
  })
  
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-default-sa-role"
  })
}

# IRSA Role for application service accounts
resource "aws_iam_role" "app_service_account" {
  count = var.enable_irsa ? 1 : 0
  
  name = "${var.cluster_name}-app-sa-role"
  
  assume_role_policy = templatefile("${path.module}/policies/irsa-assume-role-policy.json.tftpl", {
    oidc_provider_arn = aws_iam_openid_connect_provider.rke_oidc[0].arn
    oidc_provider_url = aws_iam_openid_connect_provider.rke_oidc[0].url
    namespace = "default"
    service_account = "app-sa"
  })
  
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-app-sa-role"
  })
}

# S3 permissions for application service account
resource "aws_iam_role_policy" "app_s3_policy" {
  count = var.enable_irsa ? 1 : 0
  
  name = "${var.cluster_name}-app-s3-policy"
  role = aws_iam_role.app_service_account[0].id
  
  policy = templatefile("${path.module}/policies/app-s3-policy.json.tftpl", {
    bucket_name = var.app_s3_bucket
  })
} 