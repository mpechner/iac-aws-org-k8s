# cert-manager — TLS certificate lifecycle via Let's Encrypt
# IRSA annotation grants Route53 access for DNS-01 challenges.

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.20.1"
  namespace        = "cert-manager"
  create_namespace = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = data.terraform_remote_state.karpenter.outputs.irsa_cert_manager_role_arn
    },
  ]

  depends_on = [null_resource.wait_for_aws_lb_controller]
}
