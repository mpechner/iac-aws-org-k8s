# OpenVPN TLS certificate pipeline.
#
# AWS credentials come from the EC2 node IAM role (rke-nodes-role), which is scoped by
# RKE-cluster/dev-cluster/ec2 to the VPN hosted zone (Route53 DNS-01) and openvpn/* in
# Secrets Manager. No static keys or Kubernetes credential Secrets are required.
#
# Secret path:  openvpn/<env>  (aws/secretsmanager default KMS key)
# CronJob image: set openvpn_cert_publisher_image in terraform.tfvars once the image is built.

module "openvpn_cert" {
  source = "../../modules/tls-issue"

  route53_domain          = var.route53_domain
  hosted_zone_id          = var.openvpn_cert_hosted_zone_id
  environment             = var.environment
  letsencrypt_environment = var.letsencrypt_environment
  letsencrypt_email       = var.openvpn_cert_letsencrypt_email
  aws_region              = var.aws_region
  enabled                 = var.openvpn_cert_enabled
  publisher_image         = var.openvpn_cert_publisher_image

  depends_on = [module.applications]
}
