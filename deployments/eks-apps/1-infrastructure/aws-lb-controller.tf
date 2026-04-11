# AWS Load Balancer Controller
# EKS uses IRSA (not node role attachment); role ARN comes from 3-karpenter remote state.
#
# Gateway API support is explicitly disabled via the NLBGatewayAPI and ALBGatewayAPI
# feature gates. v3.x of this chart defaults these on, which makes the controller watch
# Kubernetes Gateway API CRDs like ListenerSet.gateway.networking.k8s.io at startup.
# Those specific CRDs do not exist in any Gateway API release we can match to this chart
# (the chart appears to reference a pre-release name that was renamed to XListenerSet
# under gateway.networking.x-k8s.io in Gateway API v1.3+), so enabling them sends the
# controller into an infinite CrashLoopBackOff waiting for a cache sync that will never
# happen. This stack uses Traefik for ingress and LoadBalancer-type Services for NLB
# provisioning, so nothing here depends on Gateway API — disabling it is the correct fix.

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.2.1"
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
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = data.terraform_remote_state.karpenter.outputs.irsa_aws_lbc_role_arn
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
    },
  ]

  values = [yamlencode({
    logLevel = "info"
    controllerConfig = {
      featureGates = {
        NLBGatewayAPI = false
        ALBGatewayAPI = false
      }
    }
  })]
}
