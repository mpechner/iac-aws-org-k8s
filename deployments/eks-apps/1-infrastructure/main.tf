# Stage 1: Infrastructure - Helm Charts and Load Balancers
#
# Deploys foundational infrastructure (CRDs + controllers) before Stage 2.
#
# Components:
#   - AWS Load Balancer Controller (required for NLB provisioning)
#   - cert-manager: TLS certificate management via Let's Encrypt
#   - external-dns: Automatic Route53 DNS record management
#   - Traefik: Ingress controller (external NLB for nginx, internal NLB for dashboards)
#   - KEDA: Event-driven autoscaler

# Remote state: EKS cluster (cluster endpoint + CA cert)
data "terraform_remote_state" "eks_cluster" {
  backend = "s3"
  config = {
    bucket = var.karpenter_state_bucket
    key    = var.cluster_state_key
    region = var.karpenter_state_region
  }
}

# Remote state: Karpenter layer (IRSA role ARNs)
data "terraform_remote_state" "karpenter" {
  backend = "s3"
  config = {
    bucket = var.karpenter_state_bucket
    key    = var.karpenter_state_key
    region = var.karpenter_state_region
  }
}

# VPC lookup by Name tag
data "aws_vpc" "by_name" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

locals {
  vpc_id   = data.aws_vpc.by_name.id
  role_arn = "arn:aws:iam::${var.account_id}:role/terraform-execute"
}

# Subnet discovery: by Name tag first, then kubernetes.io/role tag, then CIDR fallback
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

data "aws_subnets" "public_by_role" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:kubernetes.io/role/elb"
    values = ["1"]
  }
}

data "aws_subnets" "private_by_role" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
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

locals {
  public_subnet_ids = (
    length(data.aws_subnets.public_by_name.ids) > 0 ? data.aws_subnets.public_by_name.ids : (
      length(data.aws_subnets.public_by_role.ids) > 0 ? data.aws_subnets.public_by_role.ids :
      data.aws_subnets.public_by_cidr.ids
    )
  )
  private_subnet_ids = (
    length(data.aws_subnets.private_by_name.ids) > 0 ? data.aws_subnets.private_by_name.ids : (
      length(data.aws_subnets.private_by_role.ids) > 0 ? data.aws_subnets.private_by_role.ids :
      data.aws_subnets.private_by_cidr.ids
    )
  )
}

# Tag subnets for AWS Load Balancer Controller discovery
resource "aws_ec2_tag" "public_subnet_cluster" {
  for_each    = toset(local.public_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "private_subnet_cluster" {
  for_each    = toset(local.private_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

# Internal NLB for dashboards (Traefik, Karpenter metrics, KEDA metrics)
# Uses dev-priv-* subnets only — not dev-eks-* (those are for nodes)
resource "kubernetes_service_v1" "traefik_internal" {
  metadata {
    name      = "traefik-internal"
    namespace = "traefik"
    annotations = merge(
      {
        "service.beta.kubernetes.io/aws-load-balancer-type"                  = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-internal"              = "true"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"                = "internal"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"       = "instance"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol"  = "TCP"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"      = "traffic-port"
        "external-dns.alpha.kubernetes.io/hostname"                          = "traefik.${var.route53_domain},karpenter.${var.route53_domain},keda.${var.route53_domain},grafana.${var.route53_domain}"
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

  depends_on = [helm_release.traefik]
}

# Wait for AWS Load Balancer Controller webhook before deploying services that need NLBs
resource "null_resource" "wait_for_aws_lb_controller" {
  triggers = {
    alb_controller_id      = helm_release.aws_load_balancer_controller.id
    alb_controller_version = helm_release.aws_load_balancer_controller.version
  }

  provisioner "local-exec" {
    command = "echo 'AWS LB Controller deployed (Helm wait=true ensures pods ready); sleeping 30s for webhook registration...' && sleep 30"
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

# Wait for both Traefik NLBs (external + internal) to be active
resource "null_resource" "wait_for_nlbs" {
  triggers = {
    traefik_release  = helm_release.traefik.id
    traefik_internal = kubernetes_service_v1.traefik_internal.id
    region           = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      REGION="${var.aws_region}"
      ROLE_ARN="arn:aws:iam::${var.account_id}:role/terraform-execute"
      echo "Assuming terraform-execute role for NLB wait..."
      CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "tf-wait-nlbs" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')
      echo "Waiting for both Traefik NLBs (external + internal) to be active..."
      for i in $(seq 1 90); do
        COUNT=$(aws elbv2 describe-load-balancers --region "$REGION" \
          --query 'length(LoadBalancers[?starts_with(LoadBalancerName, `k8s-traefik`)])' \
          --output text 2>/dev/null || echo "0")
        if [ "$COUNT" = "2" ]; then
          BAD=$(aws elbv2 describe-load-balancers --region "$REGION" \
            --query 'LoadBalancers[?starts_with(LoadBalancerName, `k8s-traefik`) && State.Code!=`active`].LoadBalancerName' \
            --output text 2>/dev/null || true)
          if [ -z "$BAD" ]; then
            echo "Both NLBs are provisioned and active."
            exit 0
          fi
        fi
        echo "Waiting for NLBs... attempt $i/90 (found $COUNT)"
        sleep 5
      done
      echo "Timeout waiting for both Traefik NLBs"
      exit 1
    EOT
  }

  depends_on = [helm_release.traefik, kubernetes_service_v1.traefik_internal]
}

# ------------------------------------------------------------------------------
# DESTROY helpers
# Run scripts/delete-traefik-nlbs.sh before terraform destroy.
# ------------------------------------------------------------------------------
resource "null_resource" "pre_destroy_nlb_check" {
  triggers = {
    wait_for_nlbs = null_resource.wait_for_nlbs.id
    region        = var.aws_region
    account_id    = var.account_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      REGION="${self.triggers.region}"
      ROLE_ARN="arn:aws:iam::${self.triggers.account_id}:role/terraform-execute"
      CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "tf-destroy-nlb-check" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')
      COUNT=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query 'length(LoadBalancers[?starts_with(LoadBalancerName, `k8s-traefik`)])' \
        --output text 2>/dev/null || echo "0")
      if [ "$COUNT" != "0" ]; then
        echo ""
        echo "*** WARNING: $COUNT Traefik NLB(s) still exist. Run scripts/delete-traefik-nlbs.sh first. ***"
        echo "  AWS_ASSUME_ROLE_ARN=\"$ROLE_ARN\" ./scripts/delete-traefik-nlbs.sh"
        echo "Then run terraform destroy again."
        echo ""
        exit 1
      fi
      echo "No Traefik NLBs found; proceeding with destroy."
    EOT
  }

  depends_on = [null_resource.wait_for_nlbs]
}

resource "null_resource" "cleanup_nlbs_on_destroy" {
  triggers = {
    traefik_internal = kubernetes_service_v1.traefik_internal.id
    traefik_release  = helm_release.traefik.id
    region           = var.aws_region
    account_id       = var.account_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      REGION="${self.triggers.region}"
      ROLE_ARN="arn:aws:iam::${self.triggers.account_id}:role/terraform-execute"
      CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "tf-destroy-cleanup" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')
      COUNT=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query 'length(LoadBalancers[?starts_with(LoadBalancerName, `k8s-traefik`)])' \
        --output text 2>/dev/null || echo "0")
      if [ "$COUNT" != "0" ]; then
        echo "*** WARNING: $COUNT Traefik NLB(s) still exist. Run scripts/delete-traefik-nlbs.sh first. ***"
        echo "  AWS_ASSUME_ROLE_ARN=\"$ROLE_ARN\" ./scripts/delete-traefik-nlbs.sh"
        exit 1
      fi
      echo "Stripping LoadBalancer Service finalizers..."
      for i in $(seq 1 18); do
        kubectl patch svc -n traefik traefik-internal -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
        kubectl patch svc -n traefik traefik          -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
        sleep 10
      done
      echo "Cleanup done."
    EOT
  }
}

# Diagnostic outputs
output "vpc_id_resolved" {
  value       = local.vpc_id
  description = "VPC ID used for subnet discovery"
}

output "debug_public_subnets" {
  value       = local.public_subnet_ids
  description = "Public subnet IDs (external NLB)"
}

output "debug_private_subnets" {
  value       = local.private_subnet_ids
  description = "Private subnet IDs (internal NLB)"
}
