# Stage 1: Infrastructure - Helm Charts and Load Balancers
#
# This stage deploys the foundational infrastructure that installs
# Custom Resource Definitions (CRDs) needed by Stage 2.
#
# Deployed components:
#   - cert-manager: Certificate management and Let's Encrypt integration
#   - external-dns: Automatic Route53 DNS record management
#   - Traefik: Ingress controller with public and internal load balancers

# Resolve VPC the same way as RKE: by tag Name (e.g. "dev") so we use the same VPC and find subnets reliably
data "aws_vpc" "by_name" {
  count = var.vpc_name != null && var.vpc_name != "" ? 1 : 0
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}
locals {
  vpc_id = var.vpc_name != null && var.vpc_name != "" ? data.aws_vpc.by_name[0].id : var.vpc_id
}

# Subnet discovery in resolved VPC: by exact Name tags (matches VPC/dev) first, then role tags, then CIDR
data "aws_subnets" "public_by_name" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = var.public_subnet_names
  }
}
data "aws_subnets" "private_by_name" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = var.private_subnet_names
  }
}
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:kubernetes.io/role/elb"
    values = ["1"]
  }
}
data "aws_subnets" "public_by_cidr" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "cidr-block"
    values = var.public_subnet_cidrs
  }
}
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }
}
data "aws_subnets" "private_by_cidr" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "cidr-block"
    values = var.private_subnet_cidrs
  }
}

# Subnet IDs for NLB annotations: passed IDs > name lookup > role-tag > CIDR (so we find and annotate correctly)
locals {
  public_subnet_ids = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : (
    length(data.aws_subnets.public_by_name.ids) > 0 ? data.aws_subnets.public_by_name.ids : (
      length(data.aws_subnets.public.ids) > 0 ? data.aws_subnets.public.ids : data.aws_subnets.public_by_cidr.ids
    )
  )
  private_subnet_ids = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : (
    length(data.aws_subnets.private_by_name.ids) > 0 ? data.aws_subnets.private_by_name.ids : (
      length(data.aws_subnets.private.ids) > 0 ? data.aws_subnets.private.ids : data.aws_subnets.private_by_cidr.ids
    )
  )
}

# Tag subnets for AWS Load Balancer Controller discovery (VPC sets role tags; we set cluster tag)
resource "aws_ec2_tag" "public_subnet_cluster" {
  for_each    = length(local.public_subnet_ids) > 0 ? toset(local.public_subnet_ids) : toset([])
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}
resource "aws_ec2_tag" "private_subnet_cluster" {
  for_each    = length(local.private_subnet_ids) > 0 ? toset(local.private_subnet_ids) : toset([])
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

# Diagnostic outputs to debug subnet resolution
output "vpc_id_resolved" {
  value       = local.vpc_id
  description = "VPC ID used for subnet discovery (from vpc_name lookup or vpc_id)"
}
output "debug_public_subnets" {
  value       = local.public_subnet_ids
  description = "Public subnet IDs (used in Traefik Helm values for public NLB)"
}
output "debug_public_subnet_annotation" {
  value       = length(local.public_subnet_ids) > 0 ? "service.beta.kubernetes.io/aws-load-balancer-subnets = ${join(",", local.public_subnet_ids)}" : "none"
  description = "Annotation applied to public Traefik Service via Helm values"
}

output "debug_private_subnets" {
  value       = local.private_subnet_ids
  description = "Private subnet IDs found by data source"
}

output "debug_public_subnet_count" {
  value       = length(local.public_subnet_ids)
  description = "Number of public subnets found"
}

output "debug_private_subnet_count" {
  value       = length(local.private_subnet_ids)
  description = "Number of private subnets found"
}
module "cert_manager" {
  source = "../../../modules/ingress/cert-manager"

  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  chart_version    = "v1.15.3"
  install_crds     = true
  set              = []
  values           = []

  depends_on = [helm_release.aws_load_balancer_controller, null_resource.wait_for_aws_lb_controller]
}

# Deploy external-dns in its own namespace
module "external_dns" {
  source = "../../../modules/ingress/external-dns"

  name             = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  chart_version    = "1.15.0"
  set = [
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
  ]
  values = []

  depends_on = [helm_release.aws_load_balancer_controller, null_resource.wait_for_aws_lb_controller]
}

# Deploy Traefik ingress controller in its own namespace
module "traefik" {
  source = "../../../modules/ingress/traefik"

  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  chart_version    = "24.0.0"
  service_type     = "LoadBalancer"
  set = [
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
  ]
  values = [yamlencode({
    service = {
      annotations = length(local.public_subnet_ids) > 0 ? {
        "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", local.public_subnet_ids)
      } : {}
      spec = {
        loadBalancerClass = "service.k8s.aws/nlb"
      }
    }
  })]

  depends_on = [helm_release.aws_load_balancer_controller, null_resource.wait_for_aws_lb_controller]
}

# Additional internal service for Traefik dashboard and RKE server access
resource "kubernetes_service_v1" "traefik_internal" {
  metadata {
    name      = "traefik-internal"
    namespace = "traefik"
    annotations = merge(
      {
        "service.beta.kubernetes.io/aws-load-balancer-type"     = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"   = "internal"
        "external-dns.alpha.kubernetes.io/hostname"             = "traefik.${var.route53_domain},rancher.${var.route53_domain}"
      },
      length(local.private_subnet_ids) > 0 ? {
        "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", local.private_subnet_ids)
      } : {}
    )
  }

  spec {
    type                = "LoadBalancer"
    load_balancer_class = "service.k8s.aws/nlb"
    selector = {
      "app.kubernetes.io/name"     = "traefik"
      "app.kubernetes.io/instance" = "traefik"
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

# Wait for AWS Load Balancer Controller webhook to be ready
resource "null_resource" "wait_for_aws_lb_controller" {
  triggers = {
    # Re-trigger the wait if AWS LB controller helm release changes
    alb_controller_id = helm_release.aws_load_balancer_controller.id
    alb_controller_version = helm_release.aws_load_balancer_controller.version
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for AWS Load Balancer Controller webhook to be ready..."
      for i in {1..60}; do
        ENDPOINTS=$(kubectl get endpoints -n kube-system aws-load-balancer-webhook-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
        if [ $ENDPOINTS -gt 0 ]; then
          echo "AWS Load Balancer Controller webhook is ready"
          sleep 5  # Additional buffer for webhook to fully initialize
          exit 0
        fi
        echo "Waiting for webhook endpoints... attempt $i/60"
        sleep 2
      done
      echo "Timeout waiting for AWS Load Balancer Controller webhook"
      exit 1
    EOT
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}
