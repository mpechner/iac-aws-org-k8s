# Nginx sample site module
# Deploys nginx with a sample landing page and creates an ingress

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
  }
}

locals {
  app_name = "nginx-sample"
  labels = merge({
    app         = local.app_name
    environment = var.environment
  }, var.labels)
  
  # Backend TLS certificate is managed by ingress module
  # Secret name format: {service_name}-backend-tls
  backend_tls_secret = "${local.app_name}-backend-tls"
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.this[0].metadata[0].name : var.namespace
}

resource "kubernetes_config_map" "html" {
  metadata {
    name      = "${local.app_name}-html"
    namespace = local.namespace
    labels    = local.labels
  }

  data = {
    "index.html" = templatefile("${path.module}/site/index.html.tftpl", {
      domain      = var.domain
      hostname    = var.hostname
      environment = var.environment
      namespace   = var.namespace
      tls_enabled = true  # Always true since backend TLS is enforced
    })
  }
}

# Nginx configuration for HTTPS
resource "kubernetes_config_map" "nginx_config" {
  metadata {
    name      = "${local.app_name}-config"
    namespace = local.namespace
    labels    = local.labels
  }

  data = {
    "default.conf" = file("${path.module}/config/default.conf")
  }
}

resource "kubernetes_deployment" "this" {
  metadata {
    name      = local.app_name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = local.app_name
      }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:1.25-alpine"

          port {
            container_port = 443
            protocol       = "TCP"
          }

          volume_mount {
            name       = "html"
            mount_path = "/usr/share/nginx/html"
            read_only  = true
          }

          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/conf.d"
            read_only  = true
          }

          volume_mount {
            name       = "tls"
            mount_path = "/etc/nginx/ssl"
            read_only  = true
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }

          liveness_probe {
            http_get {
              path   = "/health"
              port   = 443
              scheme = "HTTPS"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path   = "/health"
              port   = 443
              scheme = "HTTPS"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "html"
          config_map {
            name = kubernetes_config_map.html.metadata[0].name
          }
        }

        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.nginx_config.metadata[0].name
          }
        }

        volume {
          name = "tls"
          secret {
            secret_name = local.backend_tls_secret
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "this" {
  metadata {
    name      = local.app_name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    selector = {
      app = local.app_name
    }

    port {
      port        = 443
      target_port = 443
      protocol    = "TCP"
      name        = "https"
    }

    type = "ClusterIP"
  }
}
