# TLS issuance for OpenVPN: dedicated ClusterIssuer, cert-manager Certificate,
# and CronJob to publish the issued cert to AWS Secrets Manager.
#
# AWS credentials come from the EC2 node IAM role (rke-nodes-role) — no static keys or
# credential Secrets are needed. The role must be scoped (in RKE-cluster/dev-cluster/ec2) to:
#   - Route53 ChangeResourceRecordSets on the VPN hosted zone (cert-manager DNS-01)
#   - Secrets Manager PutSecretValue/CreateSecret on openvpn/* (publisher CronJob)

locals {
  vpn_fqdn             = "vpn.${var.route53_domain}"
  tls_secret           = "openvpn-vpn-tls"
  secrets_manager_name = "openvpn/${var.environment}"
  enabled              = var.enabled
  acme_server = (
    var.letsencrypt_environment == "staging"
    ? "https://acme-staging-v02.api.letsencrypt.org/directory"
    : "https://acme-v02.api.letsencrypt.org/directory"
  )
}

# Dedicated ClusterIssuer for the VPN certificate, scoped to this hosted zone.
# Using the node IAM role (EC2 instance profile) for Route53 DNS-01 — no access key needed.
resource "kubernetes_manifest" "openvpn_clusterissuer" {
  count = local.enabled ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-vpn-${var.letsencrypt_environment}"
    }
    spec = {
      acme = {
        server = local.acme_server
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-vpn-${var.letsencrypt_environment}"
        }
        solvers = [
          {
            dns01 = {
              route53 = {
                region       = var.aws_region
                hostedZoneID = var.hosted_zone_id
              }
            }
          }
        ]
      }
    }
  }

  field_manager {
    force_conflicts = true
  }
}

resource "kubernetes_namespace_v1" "openvpn_certs" {
  count = local.enabled ? 1 : 0

  metadata {
    name = "openvpn-certs"
    labels = {
      "app.kubernetes.io/name" = "openvpn-certs"
    }
  }
}

resource "kubernetes_manifest" "openvpn_cert" {
  count = local.enabled ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "openvpn-vpn-tls"
      namespace = "openvpn-certs"
    }
    spec = {
      secretName  = local.tls_secret
      duration    = "2160h"  # 90-day certificate lifetime
      renewBefore = "720h"   # start reissue at day 60
      commonName  = local.vpn_fqdn
      dnsNames    = [local.vpn_fqdn]
      issuerRef = {
        name  = "letsencrypt-vpn-${var.letsencrypt_environment}"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.openvpn_clusterissuer,
    kubernetes_namespace_v1.openvpn_certs,
  ]
}

resource "kubernetes_manifest" "openvpn_cert_publisher_sa" {
  count = local.enabled ? 1 : 0

  manifest = {
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = "openvpn-cert-publisher"
      namespace = "openvpn-certs"
    }
  }

  depends_on = [kubernetes_namespace_v1.openvpn_certs]
}

resource "kubernetes_manifest" "openvpn_cert_publisher_role" {
  count = local.enabled ? 1 : 0

  manifest = {
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = "openvpn-cert-publisher"
      namespace = "openvpn-certs"
    }
    rules = [
      {
        apiGroups     = [""]
        resources     = ["secrets"]
        resourceNames = [local.tls_secret]
        verbs         = ["get"]
      }
    ]
  }

  depends_on = [kubernetes_namespace_v1.openvpn_certs]
}

resource "kubernetes_manifest" "openvpn_cert_publisher_rolebinding" {
  count = local.enabled ? 1 : 0

  manifest = {
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "RoleBinding"
    metadata = {
      name      = "openvpn-cert-publisher"
      namespace = "openvpn-certs"
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "Role"
      name     = "openvpn-cert-publisher"
    }
    subjects = [
      {
        kind      = "ServiceAccount"
        name      = "openvpn-cert-publisher"
        namespace = "openvpn-certs"
      }
    ]
  }

  depends_on = [kubernetes_manifest.openvpn_cert_publisher_role]
}

resource "kubernetes_manifest" "openvpn_cert_cronjob" {
  count = local.enabled && var.publisher_image != "" ? 1 : 0

  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "openvpn-publish-cert-to-secretsmanager"
      namespace = "openvpn-certs"
    }
    spec = {
      schedule                   = "*/30 * * * *"
      concurrencyPolicy          = "Forbid"
      successfulJobsHistoryLimit = 3
      failedJobsHistoryLimit     = 3
      jobTemplate = {
        spec = {
          backoffLimit             = 2
          activeDeadlineSeconds    = 300
          ttlSecondsAfterFinished  = 86400
          template = {
            spec = {
              serviceAccountName = "openvpn-cert-publisher"
              restartPolicy      = "OnFailure"
              containers = [
                {
                  name            = "publisher"
                  image           = var.publisher_image
                  imagePullPolicy = "IfNotPresent"
                  env = [
                    { name = "AWS_REGION",           value = var.aws_region },
                    { name = "AWS_SECRET_NAME",      value = local.secrets_manager_name },
                    { name = "VPN_FQDN",             value = local.vpn_fqdn },
                    { name = "TLS_SECRET_NAME",      value = local.tls_secret },
                    { name = "TLS_SECRET_NAMESPACE", value = "openvpn-certs" },
                  ]
                  volumeMounts = [
                    {
                      name      = "tls"
                      readOnly  = true
                      mountPath = "/etc/tls"
                    }
                  ]
                }
              ]
              volumes = [
                {
                  name = "tls"
                  secret = {
                    secretName = local.tls_secret
                    optional   = false
                  }
                }
              ]
            }
          }
        }
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_manifest.openvpn_cert,
    kubernetes_manifest.openvpn_cert_publisher_rolebinding,
  ]
}
