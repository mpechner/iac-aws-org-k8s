# OpenVPN TLS certificate pipeline.
#
# Uses the same tls-issue module as the RKE2 stack. EKS difference: AWS credentials
# come from IRSA (eks.amazonaws.com/role-arn annotation on the SA) rather than
# the EC2 node instance profile.
#
# IRSA role (openvpn-certs/openvpn-cert-publisher) is created in
# EKS-cluster/eks-cluster/3-karpenter/irsa.tf and scoped to:
#   - Secrets Manager PutSecretValue/CreateSecret on openvpn/*
# cert-manager DNS-01 Route53 access uses the existing irsa_cert_manager role.
#
# Secret path:  openvpn/<env>  (aws/secretsmanager default KMS key)
# CronJob image: set openvpn_cert_publisher_image in terraform.tfvars once the image is built.

locals {
  # IRSA role ARN for the cert publisher SA. Derived from account_id + cluster_name
  # to avoid hardcoding a full ARN literal in tfvars. Must match the role created in
  # EKS-cluster/eks-cluster/3-karpenter/irsa.tf (aws_iam_role.irsa_openvpn_cert_publisher).
  # Callers can override via var.openvpn_cert_publisher_irsa_role_arn if the role lives
  # under a non-default name or in a different account.
  openvpn_cert_publisher_irsa_role_arn = (
    var.openvpn_cert_publisher_irsa_role_arn != ""
    ? var.openvpn_cert_publisher_irsa_role_arn
    : "arn:aws:iam::${var.account_id}:role/${var.cluster_name}-irsa-openvpn-cert-publisher"
  )

  # Full ECR image URI for the publisher CronJob. Constructed from account_id +
  # aws_region + the <repo>:<tag> value in tfvars so the account ID lives in one place.
  # Empty var.openvpn_cert_publisher_image means "skip the CronJob" and is preserved.
  openvpn_cert_publisher_image = (
    var.openvpn_cert_publisher_image == ""
    ? ""
    : "${var.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.openvpn_cert_publisher_image}"
  )
}

module "openvpn_cert" {
  source = "../../modules/tls-issue"

  route53_domain          = var.route53_domain
  hosted_zone_id          = var.openvpn_cert_hosted_zone_id
  environment             = var.environment
  letsencrypt_environment = var.letsencrypt_environment
  letsencrypt_email       = var.openvpn_cert_letsencrypt_email
  aws_region              = var.aws_region
  enabled                 = var.openvpn_cert_enabled
  publisher_image         = local.openvpn_cert_publisher_image
  irsa_role_arn           = local.openvpn_cert_publisher_irsa_role_arn

  depends_on = [
    kubernetes_manifest.clusterissuer_staging,
    kubernetes_manifest.clusterissuer_prod,
  ]
}
