# Traefik ingress controller
#
# Dual NLB strategy:
#   External NLB (traefik service)  — public subnets, internet-facing, for nginx and public apps
#   Internal NLB (traefik-internal) — private dev-priv-* subnets, for dashboards (traefik, karpenter, keda)
#
# IRSA annotation grants traefik service account read access (no AWS API calls needed beyond OIDC).

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "39.0.5"
  namespace        = "traefik"
  create_namespace = true

  values = [yamlencode({
    api = {
      dashboard = true
    }
    image = {
      registry   = "public.ecr.aws"
      repository = "docker/library/traefik"
    }
    ports = {
      web = {
        expose = { default = true }
      }
      websecure = {
        expose = { default = true }
      }
    }
    additionalArguments = [
      "--entrypoints.web.transport.lifeCycle.requestAcceptGraceTimeout=0",
      "--entrypoints.websecure.transport.lifeCycle.requestAcceptGraceTimeout=0",
    ]
    providers = {
      kubernetesCRD = {
        allowCrossNamespace = true
      }
    }
    # Pin Traefik to on-demand nodes so it is never interrupted during business hours
    nodeSelector = {
      "nodepool" = "on-demand-stable"
    }
    # Built-in dashboard IngressRoute disabled; defined in 2-applications with TLS
    ingressRoute = {
      dashboard = {
        enabled = false
      }
    }
    # External NLB: internet-facing, public subnets, for nginx.dev.foobar.support
    service = {
      annotations = merge(
        length(local.public_subnet_ids) > 0 ? {
          "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", local.public_subnet_ids)
        } : {},
        {
          "service.beta.kubernetes.io/aws-load-balancer-type"                  = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"                = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"       = "instance"
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol"  = "TCP"
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"      = "traffic-port"
          "external-dns.alpha.kubernetes.io/hostname"                          = "nginx.${var.route53_domain}"
        }
      )
      spec = {
        loadBalancerClass = "service.k8s.aws/nlb"
      }
    }
  })]

  depends_on = [null_resource.wait_for_aws_lb_controller]
}
