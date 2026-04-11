# Stage 2: Applications — Kubernetes manifests and workloads
#
# IMPORTANT: Deploy Stage 1 (1-infrastructure) first.
#
# Remote state: EKS cluster (cluster endpoint + CA cert)
data "terraform_remote_state" "eks_cluster" {
  backend = "s3"
  config = {
    bucket = var.cluster_state_bucket
    key    = var.cluster_state_key
    region = var.cluster_state_region
  }
}

# Deployed components:
#   - ClusterIssuers: Let's Encrypt staging and prod
#   - Namespaces: nginx-sample
#   - nginx: sample app on external NLB (nginx.dev.foobar.support)
#   - Traefik dashboard: internal NLB (traefik.dev.foobar.support)
#   - Karpenter metrics: internal NLB (karpenter.dev.foobar.support)
#   - KEDA metrics: internal NLB (keda.dev.foobar.support)
#   - HTTP→HTTPS redirect middleware for all internal hosts

# ── ClusterIssuers ────────────────────────────────────────────────────────────

resource "kubernetes_manifest" "clusterissuer_staging" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        email  = var.letsencrypt_email
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-staging-key"
        }
        solvers = [
          {
            dns01 = {
              route53 = {
                region = var.aws_region
              }
            }
          }
        ]
      }
    }
  }
}

resource "kubernetes_manifest" "clusterissuer_prod" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.letsencrypt_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-key"
        }
        solvers = [
          {
            dns01 = {
              route53 = {
                region = var.aws_region
              }
            }
          }
        ]
      }
    }
  }
}

# ── Namespaces ────────────────────────────────────────────────────────────────

resource "kubernetes_namespace_v1" "nginx_sample" {
  metadata {
    name = "nginx-sample"
    labels = {
      app         = "nginx-sample"
      environment = var.environment
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

# ── nginx sample app ──────────────────────────────────────────────────────────

resource "kubernetes_deployment_v1" "nginx_sample" {
  metadata {
    name      = "nginx-sample"
    namespace = kubernetes_namespace_v1.nginx_sample.metadata[0].name
    labels = {
      app = "nginx-sample"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nginx-sample"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx-sample"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "public.ecr.aws/nginx/nginx:stable-alpine"

          port {
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "nginx_sample" {
  metadata {
    name      = "nginx-sample"
    namespace = kubernetes_namespace_v1.nginx_sample.metadata[0].name
  }

  spec {
    selector = {
      app = "nginx-sample"
    }

    port {
      port        = 80
      target_port = 80
    }
  }
}

# ── Traefik Middlewares ───────────────────────────────────────────────────────
# Moved here from 1-infrastructure: kubernetes_manifest validates CRDs at plan
# time, so these must run after Traefik (deployed in 1-infrastructure) installs
# the traefik.io CRDs.

resource "kubernetes_manifest" "traefik_security_headers" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "security-headers"
      namespace = "traefik"
    }
    spec = {
      headers = {
        customFrameOptionsValue = "SAMEORIGIN"
        contentTypeNosniff      = true
        browserXssFilter        = true
        referrerPolicy          = "strict-origin-when-cross-origin"
        stsSeconds              = 31536000
        stsIncludeSubdomains    = true
        stsPreload              = true
        contentSecurityPolicy   = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'self'; base-uri 'self'; form-action 'self';"
        customResponseHeaders = {
          "X-Frame-Options"           = "SAMEORIGIN"
          "X-Content-Type-Options"    = "nosniff"
          "X-XSS-Protection"          = "1; mode=block"
          "Strict-Transport-Security" = "max-age=31536000; includeSubDomains; preload"
          "Referrer-Policy"           = "strict-origin-when-cross-origin"
          "Permissions-Policy"        = "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
        }
      }
    }
  }
}

resource "kubernetes_manifest" "block_trace_middleware" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "block-trace"
      namespace = "traefik"
    }
    spec = {
      errors = {
        status = ["405"]
        service = {
          name = "error@internal"
          kind = "TraefikService"
        }
        query = "/405"
      }
    }
  }
}

resource "kubernetes_manifest" "block_trace_global" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "block-trace-global"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["web", "websecure"]
      routes = [
        {
          match    = "Method(`TRACE`)"
          kind     = "Rule"
          priority = 0
          middlewares = [
            {
              name      = "block-trace"
              namespace = "traefik"
            }
          ]
          services = [
            {
              name = "noop@internal"
              kind = "TraefikService"
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.block_trace_middleware]
}

# ── HTTP→HTTPS redirect middleware ────────────────────────────────────────────

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
}

# HTTP redirect for internal dashboard hosts
resource "kubernetes_manifest" "redirect_http_internal" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "redirect-http-internal"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["web"]
      routes = [
        {
          match = "Host(`traefik.${var.route53_domain}`) || Host(`karpenter.${var.route53_domain}`) || Host(`keda.${var.route53_domain}`)"
          kind  = "Rule"
          middlewares = [
            {
              name      = "redirect-http-to-https"
              namespace = "traefik"
            }
          ]
          services = [
            {
              name = "noop@internal"
              kind = "TraefikService"
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.redirect_http_to_https]
}

# ── Traefik Dashboard ─────────────────────────────────────────────────────────

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
      dnsNames   = ["traefik.${var.route53_domain}"]
      issuerRef = {
        name  = "letsencrypt-${var.letsencrypt_environment}"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [kubernetes_manifest.clusterissuer_staging, kubernetes_manifest.clusterissuer_prod]
}

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
          middlewares = [
            {
              name      = "security-headers"
              namespace = "traefik"
            }
          ]
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

  depends_on = [kubernetes_manifest.traefik_dashboard_cert, kubernetes_manifest.traefik_security_headers]
}

# ── Karpenter metrics dashboard ───────────────────────────────────────────────
# Exposes Karpenter's Prometheus metrics endpoint via the internal NLB.

resource "kubernetes_manifest" "karpenter_metrics_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "karpenter-metrics-tls"
      namespace = "traefik"
    }
    spec = {
      secretName = "karpenter-metrics-tls"
      dnsNames   = ["karpenter.${var.route53_domain}"]
      issuerRef = {
        name  = "letsencrypt-${var.letsencrypt_environment}"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [kubernetes_manifest.clusterissuer_staging, kubernetes_manifest.clusterissuer_prod]
}

resource "kubernetes_manifest" "karpenter_metrics_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "karpenter-metrics"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match    = "Host(`karpenter.${var.route53_domain}`) && PathPrefix(`/`)"
          kind     = "Rule"
          priority = 100
          middlewares = [
            {
              name      = "security-headers"
              namespace = "traefik"
            }
          ]
          services = [
            {
              name      = "karpenter"
              namespace = "karpenter"
              port      = 8080
            }
          ]
        }
      ]
      tls = {
        secretName = "karpenter-metrics-tls"
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_metrics_cert, kubernetes_manifest.traefik_security_headers]
}

# ── KEDA metrics dashboard ────────────────────────────────────────────────────
# Exposes KEDA's metrics API via the internal NLB.

resource "kubernetes_manifest" "keda_metrics_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "keda-metrics-tls"
      namespace = "traefik"
    }
    spec = {
      secretName = "keda-metrics-tls"
      dnsNames   = ["keda.${var.route53_domain}"]
      issuerRef = {
        name  = "letsencrypt-${var.letsencrypt_environment}"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [kubernetes_manifest.clusterissuer_staging, kubernetes_manifest.clusterissuer_prod]
}

resource "kubernetes_manifest" "keda_metrics_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "keda-metrics"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match    = "Host(`keda.${var.route53_domain}`) && PathPrefix(`/`)"
          kind     = "Rule"
          priority = 100
          middlewares = [
            {
              name      = "security-headers"
              namespace = "traefik"
            }
          ]
          services = [
            {
              name      = "keda-operator-metrics-apiserver"
              namespace = "keda"
              port      = 8080
            }
          ]
        }
      ]
      tls = {
        secretName = "keda-metrics-tls"
      }
    }
  }

  depends_on = [kubernetes_manifest.keda_metrics_cert, kubernetes_manifest.traefik_security_headers]
}

# ── nginx on external NLB ─────────────────────────────────────────────────────

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

  depends_on = [kubernetes_manifest.clusterissuer_staging, kubernetes_manifest.clusterissuer_prod]
}

# HTTP route for nginx (works before TLS cert is ready; useful for initial smoke test)
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

  depends_on = [kubernetes_service_v1.nginx_sample]
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
          middlewares = [
            {
              name      = "security-headers"
              namespace = "traefik"
            }
          ]
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

  depends_on = [kubernetes_manifest.nginx_cert, kubernetes_manifest.traefik_security_headers]
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "nginx_url" {
  value       = "https://nginx.${var.route53_domain}"
  description = "nginx sample app URL (external NLB)"
}

output "dashboard_urls" {
  value = {
    traefik   = "https://traefik.${var.route53_domain}/dashboard/"
    karpenter = "https://karpenter.${var.route53_domain}/metrics"
    keda      = "https://keda.${var.route53_domain}/metrics"
  }
  description = "Internal dashboard URLs (accessible via VPN / internal NLB only)"
}
