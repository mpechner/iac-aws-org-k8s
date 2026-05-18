# metrics-server — implements the Kubernetes Metrics API (metrics.k8s.io).
# Powers `kubectl top`, HPA, and KEDA's `cpu`/`memory` triggers. Separate from
# the Alloy → Mimir pipeline, which serves the Prometheus query API for
# dashboards and `prometheus`-type KEDA triggers.
#
# `--kubelet-insecure-tls`: EKS kubelets serve a cert that isn't signed by the
# cluster CA out of the box. Skipping verification is the documented pattern
# for metrics-server on EKS and is safe inside the cluster network boundary.

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.12.2"
  namespace        = "kube-system"
  create_namespace = false

  # Use values YAML instead of set blocks — the helm provider's set parser
  # treats commas as list separators, which breaks the InternalIP,ExternalIP,Hostname arg.
  values = [yamlencode({
    args = [
      "--kubelet-insecure-tls",
      "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
      "--metric-resolution=15s",
    ]
  })]

  depends_on = [null_resource.wait_for_aws_lb_controller]
}
