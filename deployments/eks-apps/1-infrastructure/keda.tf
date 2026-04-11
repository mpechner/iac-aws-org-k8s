# KEDA — event-driven autoscaler
# IRSA annotation grants SQS and CloudWatch read access for ScaledObject triggers.

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.19.0"
  namespace        = "keda"
  create_namespace = true

  set = [
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = data.terraform_remote_state.karpenter.outputs.irsa_keda_role_arn
    },
    # Operator service account (keda-operator) carries the IRSA role
    {
      name  = "operator.replicaCount"
      value = "1"
    },
  ]

  depends_on = [null_resource.wait_for_aws_lb_controller]
}
