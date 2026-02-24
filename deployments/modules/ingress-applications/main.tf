terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
  }
}

locals {
  # Group ingresses by namespace for backend TLS resources
  namespaces = toset([for k, v in var.ingresses : try(v.namespace, "default")])
  
  ingresses = {
    for name, ingress in var.ingresses : name => {
      name               = name
      namespace          = try(ingress.namespace, "default")
      host               = ingress.host
      service_name       = ingress.service_name
      service_port       = ingress.service_port
      path               = ingress.path != null ? ingress.path : "/"
      path_type          = ingress.path_type != null ? ingress.path_type : "Prefix"
      ingress_class_name = ingress.ingress_class_name != null ? ingress.ingress_class_name : "traefik"
      tls_secret_name = (
        try(ingress.tls_secret_name, null) != null
        ? ingress.tls_secret_name
        : (try(ingress.cluster_issuer, null) != null ? "${name}-tls" : null)
      )
      backend_tls_enabled = ingress.backend_tls_enabled != null ? ingress.backend_tls_enabled : true
      cluster_issuer = try(ingress.cluster_issuer, null)
      annotations    = try(ingress.annotations, {})
    }
  }
}

# Create ClusterIssuer for Let's Encrypt
resource "kubernetes_manifest" "letsencrypt_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-${var.letsencrypt_environment}"
    }
    spec = {
      acme = {
        server = var.letsencrypt_environment == "staging" ? "https://acme-staging-v02.api.letsencrypt.org/directory" : "https://acme-v02.api.letsencrypt.org/directory"
        email = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-${var.letsencrypt_environment}"
        }
        solvers = [
          {
            dns01 = {
              route53 = {
                region = var.aws_region
              }
            }
            selector = {
              dnsNames = []
            }
          }
        ]
      }
    }
  }
}

# Backend TLS Infrastructure (per namespace)
# Self-signed Issuer for creating CAs
resource "kubernetes_manifest" "backend_ca_issuer" {
  for_each = local.namespaces

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "backend-ca-selfsigned"
      namespace = each.value
    }
    spec = {
      selfSigned = {}
    }
  }

  depends_on = [kubernetes_manifest.letsencrypt_issuer]
}

# CA Certificate for backend TLS (per namespace)
resource "kubernetes_manifest" "backend_ca_cert" {
  for_each = local.namespaces

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "backend-ca"
      namespace = each.value
    }
    spec = {
      isCA       = true
      commonName = "backend-ca-${each.value}"
      secretName = "backend-ca-secret"
      duration   = "87600h" # 10 years
      privateKey = {
        algorithm = "RSA"
        size      = 2048
      }
      issuerRef = {
        name  = kubernetes_manifest.backend_ca_issuer[each.value].manifest.metadata.name
        kind  = "Issuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [kubernetes_manifest.backend_ca_issuer]
}

# CA Issuer for signing backend certificates (per namespace)
resource "kubernetes_manifest" "backend_issuer" {
  for_each = local.namespaces

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "backend-issuer"
      namespace = each.value
    }
    spec = {
      ca = {
        secretName = kubernetes_manifest.backend_ca_cert[each.value].manifest.spec.secretName
      }
    }
  }

  depends_on = [kubernetes_manifest.backend_ca_cert]
}

# Backend certificates for each service with backend TLS enabled
resource "kubernetes_manifest" "backend_cert" {
  for_each = {
    for name, ing in local.ingresses : name => ing
    if ing.backend_tls_enabled
  }

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "${each.value.service_name}-backend-tls"
      namespace = each.value.namespace
    }
    spec = {
      secretName  = "${each.value.service_name}-backend-tls"
      duration    = "8760h" # 1 year
      renewBefore = "720h"  # 30 days
      commonName  = "${each.value.service_name}.${each.value.namespace}.svc.cluster.local"
      dnsNames = [
        each.value.service_name,
        "${each.value.service_name}.${each.value.namespace}",
        "${each.value.service_name}.${each.value.namespace}.svc",
        "${each.value.service_name}.${each.value.namespace}.svc.cluster.local",
      ]
      privateKey = {
        algorithm = "RSA"
        size      = 2048
      }
      usages = [
        "digital signature",
        "key encipherment",
        "server auth",
      ]
      issuerRef = {
        name  = kubernetes_manifest.backend_issuer[each.value.namespace].manifest.metadata.name
        kind  = "Issuer"
        group = "cert-manager.io"
      }
    }
  }

  depends_on = [kubernetes_manifest.backend_issuer]
}

# ServersTransport for backend HTTPS (per namespace)
resource "kubernetes_manifest" "backend_transport" {
  for_each = local.namespaces

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "ServersTransport"
    metadata = {
      name      = "backend-tls"
      namespace = each.value
    }
    spec = {
      serverName = "*.${each.value}.svc.cluster.local"
      rootCAsSecrets = [
        "backend-ca-secret"
      ]
    }
  }

  depends_on = [kubernetes_manifest.backend_ca_cert]
}

# Managed Ingress resources
resource "kubernetes_manifest" "managed_ingress" {
  for_each = local.ingresses

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = each.value.name
      namespace = each.value.namespace
      annotations = merge(
        each.value.annotations,
        {
          "external-dns.alpha.kubernetes.io/hostname" = each.value.host
        },
        each.value.cluster_issuer != null ? {
          "cert-manager.io/cluster-issuer" = each.value.cluster_issuer
        } : {},
        each.value.tls_secret_name != null ? {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
        } : {},
        each.value.backend_tls_enabled ? {
          "traefik.ingress.kubernetes.io/service.serversscheme" = "https"
        } : {}
      )
    }
    spec = merge(
      {
        ingressClassName = each.value.ingress_class_name != null ? each.value.ingress_class_name : null
        rules = [
          {
            host = each.value.host
            http = {
              paths = [
                {
                  path     = each.value.path
                  pathType = each.value.path_type
                  backend = {
                    service = {
                      name = each.value.service_name
                      port = {
                        number = each.value.service_port
                      }
                    }
                  }
                }
              ]
            }
          }
        ]
      },
      each.value.tls_secret_name != null ? {
        tls = [
          {
            hosts      = [each.value.host]
            secretName = each.value.tls_secret_name
          }
        ]
      } : {}
    )
  }

  depends_on = [
    kubernetes_manifest.backend_transport,
    kubernetes_manifest.backend_cert
  ]
}
