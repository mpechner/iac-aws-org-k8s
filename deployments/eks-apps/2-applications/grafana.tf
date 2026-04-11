# ── Observability stack ────────────────────────────────────────────────────────
#
# Each component in its own namespace:
#   mimir   — metrics storage  (grafana/mimir-distributed, monolithic mode)
#   loki    — log storage      (grafana/loki, single-binary)
#   grafana — dashboards UI    (grafana/grafana, datasources pre-wired)
#   alloy   — collector        (grafana/k8s-monitoring, alloy-only mode)
#
# Cross-namespace service DNS wiring:
#   Mimir (write) : http://mimir-nginx.mimir.svc.cluster.local/api/v1/push
#   Mimir (query) : http://mimir-nginx.mimir.svc.cluster.local/prometheus
#   Loki          : http://loki.loki.svc.cluster.local:3100
#
# Grafana UI  : https://grafana.<route53_domain>  (internal NLB via Traefik)
# Admin creds : kubectl get secret -n grafana grafana-admin \
#                 -o jsonpath='{.data.admin-password}' | base64 -d

# ── Namespaces ────────────────────────────────────────────────────────────────

resource "kubernetes_namespace_v1" "mimir" {
  metadata {
    name   = "mimir"
    labels = { app = "mimir", environment = var.environment }
  }
  lifecycle { ignore_changes = [metadata[0].annotations] }
}

resource "kubernetes_namespace_v1" "loki" {
  metadata {
    name   = "loki"
    labels = { app = "loki", environment = var.environment }
  }
  lifecycle { ignore_changes = [metadata[0].annotations] }
}

resource "kubernetes_namespace_v1" "grafana" {
  metadata {
    name   = "grafana"
    labels = { app = "grafana", environment = var.environment }
  }
  lifecycle { ignore_changes = [metadata[0].annotations] }
}

resource "kubernetes_namespace_v1" "alloy" {
  metadata {
    name   = "alloy"
    labels = { app = "alloy", environment = var.environment }
  }
  lifecycle { ignore_changes = [metadata[0].annotations] }
}

# ── Grafana admin secret ───────────────────────────────────────────────────────

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.grafana.metadata[0].name
  }
  data = {
    admin-user     = "admin"
    admin-password = var.grafana_admin_password
  }
  lifecycle {
    ignore_changes = [data]
  }
}

# ── Mimir ──────────────────────────────────────────────────────────────────────
# Monolithic mode: all components in a single binary, filesystem storage.
# nginx gateway handles read/write routing; service: mimir-nginx.mimir:80

resource "helm_release" "mimir" {
  name             = "mimir"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "mimir-distributed"
  version          = "5.6.0"
  namespace        = kubernetes_namespace_v1.mimir.metadata[0].name
  create_namespace = false
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      # Monolithic mode — all components in one pod
      monomode = {
        enabled  = true
        replicas = 1
        persistentVolume = {
          enabled = true
          size    = "20Gi"
        }
        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
          limits   = { memory = "2Gi" }
        }
      }

      mimir = {
        structuredConfig = {
          common = {
            storage = {
              backend = "filesystem"
            }
          }
          blocks_storage = {
            backend    = "filesystem"
            filesystem = { dir = "/data/tsdb" }
          }
          ruler_storage = {
            backend    = "filesystem"
            filesystem = { dir = "/data/ruler" }
          }
          alertmanager_storage = {
            backend    = "filesystem"
            filesystem = { dir = "/data/alertmanager" }
          }
          ingester = {
            ring = { replication_factor = 1 }
          }
          store_gateway = {
            sharding_ring = { replication_factor = 1 }
          }
        }
      }

      # Disable MinIO — using filesystem storage, not object storage
      minio = { enabled = false }

      # Disable all distributed components — monomode handles everything
      distributor     = { replicas = 0 }
      ingester        = { replicas = 0 }
      querier         = { replicas = 0 }
      query_frontend  = { replicas = 0 }
      query_scheduler = { replicas = 0 }
      store_gateway   = { replicas = 0 }
      compactor       = { replicas = 0 }
      ruler           = { replicas = 0 }
      alertmanager    = { replicas = 0 }
    })
  ]
}

# ── Loki ───────────────────────────────────────────────────────────────────────

resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = "6.25.1"
  namespace        = kubernetes_namespace_v1.loki.metadata[0].name
  create_namespace = false
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false

        commonConfig = {
          replication_factor = 1
        }

        storage = {
          type = "filesystem"
        }

        schemaConfig = {
          configs = [
            {
              from         = "2024-01-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }
      }

      singleBinary = {
        replicas = 1
        persistence = {
          enabled = true
          size    = "20Gi"
        }
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { memory = "1Gi" }
        }
      }

      # Disable HA components
      read    = { replicas = 0 }
      write   = { replicas = 0 }
      backend = { replicas = 0 }
      gateway = { enabled = false }

      lokiCanary = { enabled = false }
      test       = { enabled = false }
    })
  ]
}

# ── Grafana ────────────────────────────────────────────────────────────────────
# Datasources pre-wired to Mimir (metrics) and Loki (logs).

resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "8.8.4"
  namespace        = kubernetes_namespace_v1.grafana.metadata[0].name
  create_namespace = false
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      admin = {
        existingSecret = kubernetes_secret_v1.grafana_admin.metadata[0].name
        userKey        = "admin-user"
        passwordKey    = "admin-password"
      }

      persistence = {
        enabled = true
        size    = "10Gi"
      }

      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }

      ingress = { enabled = false }

      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name      = "Mimir"
              type      = "prometheus"
              url       = "http://mimir-nginx.mimir.svc.cluster.local/prometheus"
              access    = "proxy"
              isDefault = true
            },
            {
              name   = "Loki"
              type   = "loki"
              url    = "http://loki.loki.svc.cluster.local:3100"
              access = "proxy"
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    kubernetes_secret_v1.grafana_admin,
    helm_release.mimir,
    helm_release.loki,
  ]
}

# ── Alloy (k8s-monitoring, collector only) ─────────────────────────────────────
# Scrapes cluster metrics/events/logs and ships to Mimir (metrics) + Loki (logs).

resource "helm_release" "alloy" {
  name             = "alloy"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "k8s-monitoring"
  version          = "2.0.12"
  namespace        = kubernetes_namespace_v1.alloy.metadata[0].name
  create_namespace = false
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      cluster = {
        name = var.cluster_name
      }

      destinations = [
        {
          name = "mimir"
          type = "prometheus"
          url  = "http://mimir-nginx.mimir.svc.cluster.local/api/v1/push"
        },
        {
          name = "loki"
          type = "loki"
          url  = "http://loki.loki.svc.cluster.local:3100/loki/api/v1/push"
        }
      ]

      clusterMetrics = { enabled = true }
      clusterEvents  = { enabled = true }
      podLogs        = { enabled = true }

      "alloy-metrics"   = { enabled = true }
      "alloy-logs"      = { enabled = true }
      "alloy-singleton" = { enabled = true }

      # Disable bundled storage/UI — using separate releases
      grafana    = { enabled = false }
      prometheus = { enabled = false }
      loki       = { enabled = false }
    })
  ]

  depends_on = [helm_release.mimir, helm_release.loki]
}

# ── TLS certificate for Grafana ───────────────────────────────────────────────

resource "kubernetes_manifest" "grafana_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "grafana-tls"
      namespace = "traefik"
    }
    spec = {
      secretName = "grafana-tls"
      dnsNames   = ["grafana.${var.route53_domain}"]
      issuerRef = {
        name  = "letsencrypt-${var.letsencrypt_environment}"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [kubernetes_manifest.clusterissuer_staging, kubernetes_manifest.clusterissuer_prod]
}

# ── Traefik IngressRoute for Grafana ──────────────────────────────────────────

resource "kubernetes_manifest" "grafana_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "grafana"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match    = "Host(`grafana.${var.route53_domain}`) && PathPrefix(`/`)"
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
              name      = "grafana"
              namespace = kubernetes_namespace_v1.grafana.metadata[0].name
              port      = 80
            }
          ]
        }
      ]
      tls = {
        secretName = "grafana-tls"
      }
    }
  }

  depends_on = [kubernetes_manifest.grafana_cert, helm_release.grafana]
}

# ── HTTP redirect for Grafana ─────────────────────────────────────────────────

resource "kubernetes_manifest" "redirect_http_grafana" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "grafana-http-redirect"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["web"]
      routes = [
        {
          match    = "Host(`grafana.${var.route53_domain}`)"
          kind     = "Rule"
          priority = 100
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

# ── PVC cleanup on destroy ────────────────────────────────────────────────────
# Helm does NOT delete PVCs created by StatefulSet volumeClaimTemplates.
# This deletes PVCs across all observability namespaces before Terraform
# removes them, so gp3's Delete reclaim policy can clean up the EBS volumes.

resource "null_resource" "observability_pvc_cleanup" {
  triggers = {
    mimir_id     = helm_release.mimir.id
    loki_id      = helm_release.loki.id
    grafana_id   = helm_release.grafana.id
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
    account_id   = var.account_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      ROLE_ARN="arn:aws:iam::${self.triggers.account_id}:role/terraform-execute"
      CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" \
        --role-session-name "tf-destroy-obs-pvcs" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')

      aws eks update-kubeconfig \
        --name "${self.triggers.cluster_name}" \
        --region "${self.triggers.aws_region}" \
        --kubeconfig /tmp/kubeconfig-obs-cleanup

      for NS in mimir loki grafana alloy; do
        echo "Deleting PVCs in namespace $NS..."
        KUBECONFIG=/tmp/kubeconfig-obs-cleanup \
          kubectl delete pvc --all -n "$NS" --ignore-not-found --wait=false
      done

      echo "PVC cleanup complete."
      rm -f /tmp/kubeconfig-obs-cleanup
    EOT
  }

  depends_on = [helm_release.mimir, helm_release.loki, helm_release.grafana, helm_release.alloy]
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "grafana_url" {
  value       = "https://grafana.${var.route53_domain}"
  description = "Grafana UI (internal NLB — accessible via VPN)"
}
