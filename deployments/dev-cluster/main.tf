module "ingress" {
  source = "../../modules/ingress"

  aws_region       = var.aws_region
  route53_zone_id  = var.route53_zone_id
  route53_domain   = var.route53_domain
  route53_assume_role_arn = var.route53_assume_role_arn

  letsencrypt_email       = var.letsencrypt_email
  letsencrypt_environment = var.letsencrypt_environment

  # Managed ingresses (including nginx-sample)
  ingresses = {
    nginx-sample = {
      namespace          = "nginx-sample"
      host               = "www.${var.route53_domain}"
      service_name       = "nginx-sample"
      service_port       = 443
      cluster_issuer     = "letsencrypt-${var.letsencrypt_environment}"
      backend_tls_enabled = true
    }
  }
}

# Nginx sample site (deployment only, ingress handled above)
module "nginx_sample" {
  source = "./modules/nginx-sample"

  namespace   = "nginx-sample"
  environment = var.environment
  domain      = var.route53_domain
  hostname    = "www.${var.route53_domain}"

  depends_on = [module.ingress]
}
