terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
  }
}

locals {
  external_dns_set = concat(var.external_dns_set, [
    {
      name  = "provider"
      value = "aws"
      type  = "string"
    },
    {
      name  = "aws.region"
      value = var.aws_region
      type  = "string"
    },
    {
      name  = "aws.zoneType"
      value = "public"
      type  = "string"
    },
    {
      name  = "policy"
      value = "upsert-only"
      type  = "string"
    },
    {
      name  = "registry"
      value = "txt"
      type  = "string"
    },
    {
      name  = "txt-owner-id"
      value = "external-dns"
      type  = "string"
    }
  ], var.route53_assume_role_arn != null ? [
    {
      name  = "aws.assumeRoleArn"
      value = var.route53_assume_role_arn
      type  = "string"
    }
  ] : [])

  route53_solver = merge(
    { region = var.aws_region },
    var.route53_zone_id != "" ? { hostedZoneID = var.route53_zone_id } : {},
    var.route53_assume_role_arn != null ? { role = var.route53_assume_role_arn } : {}
  )

  # Group ingresses by namespace for backend TLS resources
  namespaces = toset([for k, v in var.ingresses : try(v.namespace, "default")])
  
  ingresses_by_namespace = {
    for ns in local.namespaces : ns => {
      for name, ingress in var.ingresses : name => ingress
      if try(ingress.namespace, "default") == ns
    }
  }

  ingresses = {
    for name, ingress in var.ingresses : name => {
      name               = name
      namespace          = try(ingress.namespace, "default")
      host               = ingress.host
      service_name       = ingress.service_name
      service_port       = ingress.service_port
      path               = try(ingress.path, "/")
      path_type          = try(ingress.path_type, "Prefix")
      ingress_class_name = try(ingress.ingress_class_name, "traefik")
      tls_secret_name = (
        try(ingress.tls_secret_name, null) != null
        ? ingress.tls_secret_name
        : (try(ingress.cluster_issuer, null) != null ? "${name}-tls" : null)
      )
      backend_tls_enabled = try(ingress.backend_tls_enabled, true)
      cluster_issuer = try(ingress.cluster_issuer, null)
      annotations    = try(ingress.annotations, {})
    }
  }
}

module "traefik" {
  count = var.traefik_enabled ? 1 : 0
  source = "./traefik"

  name             = var.traefik_name
  namespace        = var.traefik_namespace
  create_namespace = var.traefik_create_namespace
  repository       = var.traefik_repository
  chart            = var.traefik_chart
  chart_version    = var.traefik_chart_version
  service_type     = var.traefik_service_type
  set              = concat(var.traefik_set, [
    {
      name  = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
      value = "nlb"
      type  = "string"
    },
    {
      name  = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
      value = "internet-facing"
      type  = "string"
    }
  ], length(var.public_subnets) > 0 ? [
    {
      name  = "service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-subnets"
      value = join("\\,", var.public_subnets)
      type  = "string"
    }
  ] : [])
  values           = var.traefik_values
}

# Additional service for internal-only access (separate internal ALB)
resource "kubernetes_service_v1" "traefik_internal" {
  count = var.traefik_enabled && var.enable_internal_alb ? 1 : 0

  metadata {
    name      = "traefik-internal"
    namespace = var.traefik_namespace
    annotations = merge(
      {
        "service.beta.kubernetes.io/aws-load-balancer-type"     = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"   = "internal"
        "external-dns.alpha.kubernetes.io/hostname"             = join(",", var.internal_service_domains)
      },
      length(var.private_subnets) > 0 ? {
        "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", var.private_subnets)
      } : {}
    )
  }

  spec {
    type = "LoadBalancer"
    selector = {
      "app.kubernetes.io/name"     = "traefik"
      "app.kubernetes.io/instance" = var.traefik_name
    }
    port {
      name        = "web"
      port        = 80
      target_port = "web"
      protocol    = "TCP"
    }
    port {
      name        = "websecure"
      port        = 443
      target_port = "websecure"
      protocol    = "TCP"
    }
  }

  depends_on = [module.traefik]
}

module "external_dns" {
  count = var.external_dns_enabled ? 1 : 0
  source = "./external-dns"

  name             = var.external_dns_name
  namespace        = var.external_dns_namespace
  create_namespace = var.external_dns_create_namespace
  repository       = var.external_dns_repository
  chart            = var.external_dns_chart
  chart_version    = var.external_dns_chart_version
  set              = local.external_dns_set
  values           = var.external_dns_values
}

module "cert_manager" {
  count = var.cert_manager_enabled ? 1 : 0
  source = "./cert-manager"

  name             = var.cert_manager_name
  namespace        = var.cert_manager_namespace
  create_namespace = var.cert_manager_create_namespace
  repository       = var.cert_manager_repository
  chart            = var.cert_manager_chart
  chart_version    = var.cert_manager_chart_version
  install_crds     = var.cert_manager_install_crds
  set              = var.cert_manager_set
  values           = var.cert_manager_values
}

# Create ClusterIssuer for Let's Encrypt
resource "kubernetes_manifest" "letsencrypt_issuer" {
  count = var.cert_manager_enabled ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-${var.letsencrypt_environment}"
    }
    spec = {
      acme = {
        server = var.letsencrypt_environment == "staging" ? 
          "https://acme-staging-v02.api.letsencrypt.org/directory" : 
          "https://acme-v02.api.letsencrypt.org/directory"
        email = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-${var.letsencrypt_environment}"
        }
        solvers = [
          {
            dns01 = {
              route53 = local.route53_solver
            }
            selector = {
              dnsNames = []
            }
          }
        ]
      }
    }
  }

  depends_on = [module.cert_manager]
}

# Enable Traefik Dashboard
resource "kubernetes_manifest" "traefik_dashboard_middleware" {
  count = var.traefik_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "traefik-auth"
      namespace = var.traefik_namespace
    }
    spec = {
      basicAuth = {
        secret = "traefik-auth-secret"
      }
    }
  }

  depends_on = [module.traefik]
}

# Traefik Dashboard IngressRoute (internal-only)
resource "kubernetes_manifest" "traefik_dashboard_ingressroute" {
  count = var.traefik_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "traefik-dashboard"
      namespace = var.traefik_namespace
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "Host(`traefik.${var.route53_domain}`)"
          kind  = "Rule"
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

  depends_on = [module.traefik]
}

# Certificate for Traefik Dashboard
resource "kubernetes_manifest" "traefik_dashboard_cert" {
  count = var.traefik_enabled && var.cert_manager_enabled ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "traefik-dashboard-tls"
      namespace = var.traefik_namespace
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

  depends_on = [kubernetes_manifest.letsencrypt_issuer]
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

  depends_on = [module.cert_manager]
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
        each.value.cluster_issuer != null ? {
          "cert-manager.io/cluster-issuer" = each.value.cluster_issuer
        } : {},
        each.value.backend_tls_enabled ? {
          "traefik.ingress.kubernetes.io/router.entrypoints"   = "websecure"
          "traefik.ingress.kubernetes.io/service.serversscheme" = "https"
        } : {}
      )
    }
    spec = merge(
      {
        ingressClassName = each.value.ingress_class_name
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
    module.traefik,
    module.cert_manager,
    kubernetes_manifest.backend_transport,
    kubernetes_manifest.backend_cert
  ]
}


