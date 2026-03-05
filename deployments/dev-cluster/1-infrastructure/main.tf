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
    },
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
  chart_version    = "30.0.0" # Traefik v3.1: uses EndpointSlices (fixes "v1 Endpoints is deprecated" warning on k8s 1.33+)
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
    # Dashboard API must be enabled so api@internal exists; IngressRoute is in 2-applications (host + TLS)
    api = {
      dashboard = true
    }
    # Pull traefik image from public ECR instead of docker.io (avoids Docker Hub rate limits)
    image = {
      registry   = "public.ecr.aws"
      repository = "docker/library/traefik"
    }
    # Chart 30+ expects ports.<name>.expose as a dict keyed by service name (e.g. default: true)
    ports = {
      web = {
        expose = { default = true }
      }
      websecure = {
        expose = { default = true }
      }
    }
    # IngressRoutes in traefik namespace reference services in nginx-sample and cattle-system; required for routes to work
    providers = {
      kubernetesCRD = {
        allowCrossNamespace = true
      }
    }
    ingressRoute = {
      dashboard = {
        enabled = false
      }
    }
    service = {
      annotations = merge(
        length(local.public_subnet_ids) > 0 ? {
          "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", local.public_subnet_ids)
        } : {},
        {
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"       = "instance"
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "TCP"
          "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"     = "traffic-port"
          "external-dns.alpha.kubernetes.io/hostname"                          = "nginx.${var.route53_domain}"
        }
      )
      spec = {
        loadBalancerClass = "service.k8s.aws/nlb"
      }
    }
    # Global HTTP middleware - add security headers to all responses
    # This uses the headers middleware type which is built into Traefik
    additionalArguments = [
      "--entrypoints.websecure.http.middlewares=traefik-security-headers@kubernetescrd"
    ]
  })]

  depends_on = [helm_release.aws_load_balancer_controller, null_resource.wait_for_aws_lb_controller]
}

# Security Headers Middleware - adds OWASP recommended security headers to all responses
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
        # Prevent clickjacking attacks
        customFrameOptionsValue = "SAMEORIGIN"
        # Prevent MIME sniffing
        contentTypeNosniff = true
        # Enable XSS protection for legacy browsers
        browserXssFilter = true
        # Referrer policy
        referrerPolicy = "strict-origin-when-cross-origin"
        # Add STS header (HSTS)
        stsSeconds = 31536000
        stsIncludeSubdomains = true
        stsPreload = true
        # Content Security Policy
        contentSecurityPolicy = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'self'; base-uri 'self'; form-action 'self';"
        # Custom security headers
        customRequestHeaders = {}
        customResponseHeaders = {
          "X-Frame-Options"           = "SAMEORIGIN"
          "X-Content-Type-Options"    = "nosniff"
          "X-XSS-Protection"          = "1; mode=block"
          "Strict-Transport-Security"   = "max-age=31536000; includeSubDomains; preload"
          "Referrer-Policy"           = "strict-origin-when-cross-origin"
          "Permissions-Policy"          = "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
        }
      }
    }
  }

  depends_on = [module.traefik]
}

# Additional internal service for Traefik dashboard and RKE server access
resource "kubernetes_service_v1" "traefik_internal" {
  metadata {
    name      = "traefik-internal"
    namespace = "traefik"
      annotations = merge(
      {
        "service.beta.kubernetes.io/aws-load-balancer-type"                    = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-internal"                = "true"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"                  = "internal"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"         = "instance"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol"   = "TCP"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"        = "traffic-port"
        "external-dns.alpha.kubernetes.io/hostname"                            = "traefik.${var.route53_domain},rancher.${var.route53_domain}"
      },
      length(local.private_subnet_ids) > 0 ? {
        "service.beta.kubernetes.io/aws-load-balancer-subnets" = join(",", local.private_subnet_ids)
      } : {}
    )
  }

  spec {
    type                = "LoadBalancer"
    load_balancer_class = "service.k8s.aws/nlb"
    # Traefik Helm chart uses instance label = release-name + namespace (e.g. traefik-traefik)
    selector = {
      "app.kubernetes.io/name"     = "traefik"
      "app.kubernetes.io/instance" = "traefik-traefik"
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

# Wait for both Traefik NLBs (public + internal) to be provisioned and active before apply completes
resource "null_resource" "wait_for_nlbs" {
  triggers = {
    traefik          = "${module.traefik.namespace}/${module.traefik.name}"
    traefik_internal = kubernetes_service_v1.traefik_internal.id
    region           = var.aws_region
    role_arn         = var.aws_assume_role_arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      REGION="${var.aws_region}"
      ROLE_ARN="${var.aws_assume_role_arn}"
      echo "Assuming terraform-execute role for NLB wait..."
      CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "tf-wait-nlbs" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')
      echo "Waiting for both Traefik NLBs (public and internal) to be provisioned..."
      for i in $(seq 1 90); do
        COUNT=$(aws elbv2 describe-load-balancers --region "$REGION" \
          --query 'length(LoadBalancers[?starts_with(LoadBalancerName, `k8s-traefik`)])' --output text 2>/dev/null || echo "0")
        if [ "$COUNT" = "2" ]; then
          BAD=$(aws elbv2 describe-load-balancers --region "$REGION" \
            --query 'LoadBalancers[?starts_with(LoadBalancerName, `k8s-traefik`) && State.Code!=`active`].LoadBalancerName' --output text 2>/dev/null || true)
          if [ -z "$BAD" ]; then
            echo "Both NLBs are provisioned and active."
            exit 0
          fi
        fi
        echo "Waiting for NLBs... attempt $i/90 (found $COUNT)"
        sleep 5
      done
      echo "Timeout waiting for both NLBs"
      exit 1
    EOT
  }

  depends_on = [module.traefik, kubernetes_service_v1.traefik_internal]
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

# ------------------------------------------------------------------------------
# DESTROY: Before running terraform destroy here, delete Traefik NLBs first:
#   ./scripts/delete-traefik-nlbs.sh   (from repo root; set AWS_REGION; set AWS_ASSUME_ROLE_ARN to terraform-execute if not in cluster account)
# Then run terraform destroy. If you skip that, destroy will check for NLBs and fail with instructions if any exist.
# ------------------------------------------------------------------------------
# Run first on destroy: check for Traefik NLBs and print warning + instruction to run script if any exist.
# Created last (depends on wait_for_nlbs) so it is destroyed first.
resource "null_resource" "pre_destroy_delete_traefik_nlbs" {
  triggers = {
    wait_for_nlbs = null_resource.wait_for_nlbs.id
    region        = var.aws_region
    role_arn      = var.aws_assume_role_arn
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
        echo "Run from this directory (1-infrastructure) with the cluster account role:"
        echo "  AWS_ASSUME_ROLE_ARN=\"${self.triggers.role_arn}\" bash ../../../scripts/delete-traefik-nlbs.sh"
        echo "Or:  bash ../../../scripts/delete-traefik-nlbs.sh ${self.triggers.role_arn}"
        echo "Then run terraform destroy again."
        echo ""
        exit 1
      fi
      echo "No Traefik NLBs found; proceeding with destroy."
    EOT
  }

  depends_on = [null_resource.wait_for_nlbs]
}

# Run during destroy: strip finalizers so Services can finish deleting after NLBs are gone.
resource "null_resource" "cleanup_nlbs_on_destroy" {
  triggers = {
    traefik_internal = kubernetes_service_v1.traefik_internal.id
    traefik_release  = "${module.traefik.namespace}/${module.traefik.name}"
    region           = var.aws_region
    role_arn         = var.aws_assume_role_arn
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
      echo "Checking for Traefik NLBs before destroy..."
      COUNT=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query 'length(LoadBalancers[?starts_with(LoadBalancerName, `k8s-traefik`)])' --output text 2>/dev/null || echo "0")
      if [ "$COUNT" != "0" ]; then
        echo ""
        echo "*** WARNING: $COUNT Traefik NLB(s) still exist. Destroy may hang or leave orphaned NLBs. ***"
        echo "Run from this directory (1-infrastructure) with the cluster account role:"
        echo "  AWS_ASSUME_ROLE_ARN=\"${self.triggers.role_arn}\" bash ../../../scripts/delete-traefik-nlbs.sh"
        echo "Or:  bash ../../../scripts/delete-traefik-nlbs.sh ${self.triggers.role_arn}"
        echo "Then run terraform destroy again."
        echo ""
        exit 1
      fi
      echo "No Traefik NLBs found; stripping finalizers from LoadBalancer Services (retry for 3 min)..."
      for i in $(seq 1 18); do
        kubectl patch svc -n traefik traefik-internal -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
        kubectl patch svc -n traefik traefik -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
        sleep 10
      done
      echo "Cleanup done."
    EOT
  }
}
