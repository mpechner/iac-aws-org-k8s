# external-dns — automatic Route53 DNS record management
# IRSA annotation grants Route53 ChangeResourceRecordSets for dev.foobar.support.

resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = "1.20.0"
  namespace        = "external-dns"
  create_namespace = true

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
      value = "external-dns-dev"
      type  = "string"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = data.terraform_remote_state.karpenter.outputs.irsa_external_dns_role_arn
    },
  ]

  depends_on = [null_resource.wait_for_aws_lb_controller]
}
