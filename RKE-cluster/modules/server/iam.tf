# IAM Policies for RKE Server Nodes

# Basic EC2 permissions for server nodes
resource "aws_iam_role_policy" "rke_server_ec2" {
  name = "${var.cluster_name}-rke-server-ec2-policy"
  role = aws_iam_role.rke_server.id
  
  policy = file("${path.module}/policies/server-ec2-policy.json")
}

# ECR permissions for pulling container images
resource "aws_iam_role_policy" "rke_server_ecr" {
  name = "${var.cluster_name}-rke-server-ecr-policy"
  role = aws_iam_role.rke_server.id
  
  policy = file("${path.module}/policies/server-ecr-policy.json")
}

# CloudWatch permissions for logging and metrics
resource "aws_iam_role_policy" "rke_server_cloudwatch" {
  name = "${var.cluster_name}-rke-server-cloudwatch-policy"
  role = aws_iam_role.rke_server.id
  
  policy = file("${path.module}/policies/server-cloudwatch-policy.json")
}

# Systems Manager permissions for node management
resource "aws_iam_role_policy" "rke_server_ssm" {
  name = "${var.cluster_name}-rke-server-ssm-policy"
  role = aws_iam_role.rke_server.id
  
  policy = file("${path.module}/policies/server-ssm-policy.json")
}

# Route53 permissions for cert-manager and external-dns
resource "aws_iam_role_policy" "rke_server_route53" {
  name = "${var.cluster_name}-rke-server-route53-policy"
  role = aws_iam_role.rke_server.id
  
  policy = file("${path.module}/policies/server-route53-policy.json")
}

# etcd backup permissions (if using S3)
resource "aws_iam_role_policy" "rke_server_etcd_backup" {
  count = var.etcd_backup_enabled ? 1 : 0
  
  name = "${var.cluster_name}-rke-server-etcd-backup-policy"
  role = aws_iam_role.rke_server.id
  
  policy = templatefile("${path.module}/policies/etcd-backup-policy.json.tftpl", {
    backup_bucket = var.etcd_backup_bucket
  })
}

# OIDC Provider for IRSA (if not already created)
resource "aws_iam_openid_connect_provider" "rke_oidc" {
  count = var.enable_irsa ? 1 : 0
  
  url = "https://oidc.${var.cluster_name}.${var.aws_region}.amazonaws.com"
  
  client_id_list = ["sts.amazonaws.com"]
  
  thumbprint_list = [
    "9e99a48a9960b14926bb7f3b02e22da2b0ab7280",
    "a031c46782e6e6c662c2c87c76da9aa62ccabd8e"
  ]
  
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-oidc-provider"
  })
}

# IRSA Role for cluster admin service accounts
resource "aws_iam_role" "cluster_admin_service_account" {
  count = var.enable_irsa ? 1 : 0
  
  name = "${var.cluster_name}-cluster-admin-sa-role"
  
  assume_role_policy = templatefile("${path.module}/policies/irsa-assume-role-policy.json.tftpl", {
    oidc_provider_arn = aws_iam_openid_connect_provider.rke_oidc[0].arn
    oidc_provider_url = aws_iam_openid_connect_provider.rke_oidc[0].url
    namespace = "kube-system"
    service_account = "cluster-admin-sa"
  })
  
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-admin-sa-role"
  })
}

# IRSA Role for monitoring service accounts
resource "aws_iam_role" "monitoring_service_account" {
  count = var.enable_irsa ? 1 : 0
  
  name = "${var.cluster_name}-monitoring-sa-role"
  
  assume_role_policy = templatefile("${path.module}/policies/irsa-assume-role-policy.json.tftpl", {
    oidc_provider_arn = aws_iam_openid_connect_provider.rke_oidc[0].arn
    oidc_provider_url = aws_iam_openid_connect_provider.rke_oidc[0].url
    namespace = "monitoring"
    service_account = "prometheus-sa"
  })
  
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-monitoring-sa-role"
  })
}

# CloudWatch permissions for monitoring service account
resource "aws_iam_role_policy" "monitoring_cloudwatch_policy" {
  count = var.enable_irsa ? 1 : 0
  
  name = "${var.cluster_name}-monitoring-cloudwatch-policy"
  role = aws_iam_role.monitoring_service_account[0].id
  
  policy = file("${path.module}/policies/monitoring-cloudwatch-policy.json")
} 