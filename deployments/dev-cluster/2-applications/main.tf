# Stage 2: Applications - Kubernetes Manifests and Workloads
#
# This stage deploys application-level resources that depend on CRDs
# installed in Stage 1.
#
# IMPORTANT: You MUST deploy Stage 1 first!
#
# Deployed components:
#   - ClusterIssuer: Let's Encrypt certificate issuer
#   - Backend TLS: Internal service certificates
#   - Traefik Dashboard: IngressRoute with authentication
#   - Rancher: Kubernetes management UI
#   - Nginx Sample: Demo application with TLS
#   - OpenVPN cert: Certificate for vpn.<route53_domain> + CronJob to publish to Secrets Manager (see openvpn-cert.tf)

# Create namespaces
resource "kubernetes_namespace_v1" "nginx_sample" {
  metadata {
    name = "nginx-sample"
    labels = {
      app         = "nginx-sample"
      environment = var.environment
    }
  }
}

resource "kubernetes_namespace_v1" "cattle_system" {
  metadata {
    name = "cattle-system"
    labels = {
      app = "rancher"
    }
  }
}

# Traefik Dashboard Certificate
resource "kubernetes_manifest" "traefik_dashboard_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "traefik-dashboard-tls"
      namespace = "traefik"
    }
    spec = {
      secretName = "traefik-dashboard-tls"
      dnsNames = [
        "traefik.${var.route53_domain}"
      ]
      issuerRef = {
        name  = "letsencrypt-${var.letsencrypt_environment}"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [module.applications]
}

# Traefik Dashboard IngressRoute (websecure = 443). Dashboard/API at /dashboard and /api; root / also matched.
resource "kubernetes_manifest" "traefik_dashboard_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "traefik-dashboard"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match    = "Host(`traefik.${var.route53_domain}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`) || PathPrefix(`/`))"
          kind     = "Rule"
          priority = 100
          services = [
            {
              name = "api@internal"
              kind = "TraefikService"
            }
          ]
        }
      ]
      tls = {
        secretName = "traefik-dashboard-tls"
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [kubernetes_manifest.traefik_dashboard_cert]
}

# Rancher Helm Chart
resource "helm_release" "rancher" {
  name             = "rancher"
  repository       = "https://releases.rancher.com/server-charts/latest"
  chart            = "rancher"
  namespace        = kubernetes_namespace_v1.cattle_system.metadata[0].name
  create_namespace = false

  set = [
    {
      name  = "hostname"
      value = "rancher.${var.route53_domain}"
    },
    {
      name  = "bootstrapPassword"
      value = "admin"
    },
    {
      name  = "ingress.enabled"
      value = "false"
    },
    {
      name  = "tls"
      value = "ingress"
    },
    {
      name  = "replicas"
      value = "1"
    }
  ]

  depends_on = [kubernetes_namespace_v1.cattle_system]
}

# HTTP→HTTPS redirect for internal hosts (rancher, traefik dashboard)
resource "kubernetes_manifest" "redirect_http_to_https" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "redirect-http-to-https"
      namespace = "traefik"
    }
    spec = {
      redirectScheme = {
        scheme    = "https"
        permanent = true
        port      = "443"
      }
    }
  }

  depends_on = [module.applications]
}

# IngressRoute: HTTP (port 80) → redirect to HTTPS for nginx, rancher, traefik
resource "kubernetes_manifest" "redirect_http_to_https_route" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "redirect-http-to-https"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["web"]
      routes = [
        {
          match = "Host(`rancher.${var.route53_domain}`) || Host(`traefik.${var.route53_domain}`)"
          kind  = "Rule"
          middlewares = [
            {
              name      = "redirect-http-to-https"
              namespace = "traefik"
            }
          ]
          services = [
            {
              name      = "rancher"
              namespace = "cattle-system"
              port      = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.redirect_http_to_https]
}

# Nginx on HTTP (port 80) so it works even when TLS cert isn't ready. Use this to verify routing first.
resource "kubernetes_manifest" "nginx_ingressroute_http" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "nginx-http"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["web"]
      routes = [
        {
          match    = "Host(`nginx.${var.route53_domain}`) && PathPrefix(`/`)"
          kind     = "Rule"
          priority = 100
          services = [
            {
              name           = "nginx-sample"
              namespace      = "nginx-sample"
              port           = 80
              passHostHeader = true
            }
          ]
        }
      ]
    }
  }

  depends_on = [module.nginx_sample]
}

# Nginx: explicit Certificate + IngressRoute so Traefik has a direct route (avoids Ingress/class issues).
resource "kubernetes_manifest" "nginx_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "nginx-tls"
      namespace = "traefik"
    }
    spec = {
      secretName = "nginx-tls"
      dnsNames   = ["nginx.${var.route53_domain}"]
      issuerRef = {
        name  = "letsencrypt-${var.letsencrypt_environment}"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [module.applications]
}

resource "kubernetes_manifest" "nginx_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "nginx"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match    = "Host(`nginx.${var.route53_domain}`) && PathPrefix(`/`)"
          kind     = "Rule"
          priority = 100
          services = [
            {
              name           = "nginx-sample"
              namespace      = "nginx-sample"
              port           = 80
              passHostHeader = true
            }
          ]
        }
      ]
      tls = {
        secretName = "nginx-tls"
      }
    }
  }

  depends_on = [kubernetes_manifest.nginx_cert]
}

# Rancher: explicit Certificate + IngressRoute (same pattern as nginx so Traefik routes reliably).
resource "kubernetes_manifest" "rancher_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "rancher-tls"
      namespace = "traefik"
    }
    spec = {
      secretName = "rancher-tls"
      dnsNames   = ["rancher.${var.route53_domain}"]
      issuerRef = {
        name  = "letsencrypt-${var.letsencrypt_environment}"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [module.applications]
}

# Rancher on 443 (HTTPS): websecure = port 443, TLS from rancher-tls.
resource "kubernetes_manifest" "rancher_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "rancher"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match    = "Host(`rancher.${var.route53_domain}`) && PathPrefix(`/`)"
          kind     = "Rule"
          priority = 100
          services = [
            {
              name           = "rancher"
              namespace      = "cattle-system"
              port           = 80
              passHostHeader = true
            }
          ]
        }
      ]
      tls = {
        secretName = "rancher-tls"
      }
    }
  }

  depends_on = [kubernetes_manifest.rancher_cert]
}

# Applications module - Creates Ingress + cert-manager (same pattern as nginx; Rancher uses it for TLS + routing)
module "applications" {
  source = "../../modules/ingress-applications"

  route53_domain          = var.route53_domain
  letsencrypt_environment = var.letsencrypt_environment
  traefik_namespace       = "traefik"

  # Nginx and Rancher are served by explicit IngressRoutes + Certificates in traefik namespace (prod); no Ingress here.
  ingresses = {}

  depends_on = [
    kubernetes_namespace_v1.nginx_sample,
    kubernetes_namespace_v1.cattle_system,
    helm_release.rancher
  ]
}

# Nginx sample site - Deploy after certificates are ready
module "nginx_sample" {
  source = "../../modules/nginx-sample"

  namespace        = kubernetes_namespace_v1.nginx_sample.metadata[0].name
  create_namespace = false  # Namespace already created above
  environment      = var.environment
  domain           = var.route53_domain
  hostname         = "nginx.${var.route53_domain}"

  depends_on = [module.applications]
}

# ------------------------------------------------------------------------------
# DESTROY: Before running terraform destroy here, delete Traefik NLBs first:
#   ./scripts/delete-traefik-nlbs.sh   (from repo root; set AWS_REGION; set AWS_ASSUME_ROLE_ARN to terraform-execute if not in cluster account)
# Then run terraform destroy. If you skip that, destroy will check for NLBs and fail with instructions if any exist.
# ------------------------------------------------------------------------------
# Run first on destroy: check for Traefik NLBs and print warning + instruction to run script if any exist.
# Depends on all other resources so it is destroyed first (Terraform destroys dependents before dependencies).
# Then the provisioner runs; if NLBs exist it exits 1 and no other resource has been destroyed yet.
resource "null_resource" "pre_destroy_delete_traefik_nlbs" {
  triggers = {
    nginx_sample = "${module.nginx_sample.namespace}/${module.nginx_sample.service_name}"
    region       = var.aws_region
    role_arn     = var.aws_assume_role_arn
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      REGION="${self.triggers.region}"
      ROLE_ARN="${self.triggers.role_arn}"
      echo "Assuming terraform-execute role for NLB check..."
      CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "tf-destroy-nlb-check" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')
      COUNT=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query 'length(LoadBalancers[?starts_with(LoadBalancerName, `k8s-traefik`)])' --output text 2>/dev/null || echo "0")
      if [ "$COUNT" != "0" ]; then
        echo ""
        echo "*** WARNING: $COUNT Traefik NLB(s) still exist. Destroy may hang or leave orphaned NLBs. ***"
        echo "Run from this directory (2-applications) with the cluster account role:"
        echo "  AWS_ASSUME_ROLE_ARN=\"${self.triggers.role_arn}\" bash ../../../scripts/delete-traefik-nlbs.sh"
        echo "Or:  bash ../../../scripts/delete-traefik-nlbs.sh ${self.triggers.role_arn}"
        echo "Then run terraform destroy again."
        echo ""
        exit 1
      fi
      echo "No Traefik NLBs found; proceeding with destroy."
    EOT
  }

  depends_on = [
    kubernetes_namespace_v1.nginx_sample,
    kubernetes_namespace_v1.cattle_system,
    kubernetes_manifest.traefik_dashboard_cert,
    kubernetes_manifest.traefik_dashboard_ingressroute,
    helm_release.rancher,
    kubernetes_manifest.redirect_http_to_https,
    kubernetes_manifest.redirect_http_to_https_route,
    kubernetes_manifest.nginx_ingressroute_http,
    kubernetes_manifest.nginx_cert,
    kubernetes_manifest.nginx_ingressroute,
    kubernetes_manifest.rancher_cert,
    kubernetes_manifest.rancher_ingressroute,
    module.openvpn_cert,
    module.applications,
    module.nginx_sample,
  ]
}

output "nginx_url" {
  value = <<-EOT
    Try HTTP first (works without TLS):  http://nginx.${var.route53_domain}
    Then HTTPS (once cert is ready):     https://nginx.${var.route53_domain}
    (Public NLB; ensure DNS resolves to the NLB.)
  EOT
  description = "Nginx app URLs."
}

output "openvpn_cert" {
  value = var.openvpn_cert_enabled ? {
    vpn_fqdn             = module.openvpn_cert.vpn_fqdn
    namespace            = module.openvpn_cert.namespace
    tls_secret_name      = module.openvpn_cert.tls_secret_name
    secrets_manager_name = module.openvpn_cert.secrets_manager_name
    clusterissuer_name   = module.openvpn_cert.clusterissuer_name
    cronjob_name         = module.openvpn_cert.cronjob_name
  } : null
  description = "OpenVPN cert-manager + publisher (when openvpn_cert_enabled is true)."
}
