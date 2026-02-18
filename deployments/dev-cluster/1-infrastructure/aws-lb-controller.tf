# AWS Load Balancer Controller
# This is required because RKE2's cloud controller manager disables the service controller

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.11.0"
  namespace  = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = local.vpc_id
    },
    {
      name  = "enableShield"
      value = "false"
    },
    {
      name  = "enableWaf"
      value = "false"
    },
    {
      name  = "enableWafv2"
      value = "false"
    },
    {
      name  = "enableServiceMutatorWebhook"
      value = "true"
    }
  ]

  # Enable verbose logging for troubleshooting
  values = [yamlencode({
    logLevel = "debug"
  })]
}
