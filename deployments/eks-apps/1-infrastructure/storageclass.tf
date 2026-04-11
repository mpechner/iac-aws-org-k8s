# Default StorageClass for the cluster.
#
# EKS installs the aws-ebs-csi-driver addon (see EKS-cluster/eks-cluster/2-cluster/irsa.tf)
# but does not create any StorageClass objects. Without this resource, any PVC that
# does not specify a storageClass will stay Pending and Karpenter will refuse to
# schedule the pod.
#
# This StorageClass is marked as the cluster default via the is-default-class annotation,
# so Helm charts (Mimir, Loki, Grafana, etc.) do not need to set persistence.storageClass
# explicitly. Adding a new chart that needs persistence will get gp3 automatically.
#
# WaitForFirstConsumer lets Karpenter pick the AZ based on the pod that needs the volume
# rather than pinning the PVC to an AZ before any node exists.
#
# Encryption: `encrypted = "true"` with no `kmsKeyId` tells the ebs.csi.aws.com provisioner
# to use the account's default EBS encryption key (aws/ebs AWS-managed key).
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
}

# Cluster-wide PVC cleanup on destroy.
#
# The 2-applications layer has its own null_resource.observability_pvc_cleanup that handles
# mimir/loki/grafana/alloy PVCs when 2-applications is destroyed. This resource is the
# safety net for everything else: any PVC in any namespace (test workloads, future charts,
# manually-created ones) gets cleaned up before the gp3 StorageClass goes away and before
# the EBS CSI driver addon is destroyed in 2-cluster.
#
# Why this matters: PVC deletion triggers a finalizer that asks the EBS CSI controller to
# deprovision the underlying EBS volume. If the CSI controller is gone (because 2-cluster
# was already destroyed), the finalizer never completes and the PV objects get stuck in
# Terminating forever, leaking EBS volumes in AWS.
#
# Ordering: because this resource depends on kubernetes_storage_class_v1.gp3, on destroy
# Terraform tears down this null_resource first (running the cleanup), then the StorageClass,
# then any upstream resources. That guarantees PVC deletion happens while the CSI driver
# is still alive in the cluster.
resource "null_resource" "all_pvc_cleanup" {
  triggers = {
    gp3_id       = kubernetes_storage_class_v1.gp3.id
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
    account_id   = var.account_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      ROLE_ARN="arn:aws:iam::${self.triggers.account_id}:role/terraform-execute"
      CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" \
        --role-session-name "tf-destroy-all-pvcs" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')

      aws eks update-kubeconfig \
        --name "${self.triggers.cluster_name}" \
        --region "${self.triggers.aws_region}" \
        --kubeconfig /tmp/kubeconfig-all-pvc-cleanup

      export KUBECONFIG=/tmp/kubeconfig-all-pvc-cleanup

      # Delete PVCs across every namespace. `kubectl delete pvc --all` does not accept
      # --all-namespaces, so iterate. Tolerate errors on a per-namespace basis so one
      # stuck namespace does not block the rest.
      NAMESPACES=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
      for NS in $NAMESPACES; do
        PVC_COUNT=$(kubectl get pvc -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$PVC_COUNT" != "0" ] && [ -n "$PVC_COUNT" ]; then
          echo "Deleting $PVC_COUNT PVC(s) in namespace $NS..."
          kubectl delete pvc --all -n "$NS" --ignore-not-found --wait=false --timeout=60s || true
        fi
      done

      # Give the CSI driver a moment to start processing finalizers on the deletions we
      # just issued. Finalizers will continue processing asynchronously after this; we
      # only need enough time for the CSI controller to pick them up before the rest of
      # the destroy chain proceeds.
      echo "Waiting 15s for CSI finalizer processing to begin..."
      sleep 15

      rm -f /tmp/kubeconfig-all-pvc-cleanup
      echo "Cluster-wide PVC cleanup complete."
    EOT
  }

  depends_on = [kubernetes_storage_class_v1.gp3]
}

# If the cluster's EKS version shipped a pre-created `gp2` StorageClass with the default
# annotation, we end up with two default StorageClasses simultaneously, which makes the
# choice non-deterministic for PVCs that don't specify a class. Strip the default annotation
# off gp2 if it exists. No-op if gp2 is absent or already non-default.
resource "null_resource" "unset_gp2_default" {
  triggers = {
    gp3_id       = kubernetes_storage_class_v1.gp3.id
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
    account_id   = var.account_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ROLE_ARN="arn:aws:iam::${self.triggers.account_id}:role/terraform-execute"
      CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" \
        --role-session-name "tf-unset-gp2-default" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')

      aws eks update-kubeconfig \
        --name "${self.triggers.cluster_name}" \
        --region "${self.triggers.aws_region}" \
        --kubeconfig /tmp/kubeconfig-gp2-unset

      # Remove the is-default-class annotation from gp2 if present.
      # `kubectl annotate ... annotation-` removes the annotation; returns non-zero
      # only if the StorageClass itself does not exist, which we tolerate with || true.
      KUBECONFIG=/tmp/kubeconfig-gp2-unset kubectl annotate \
        storageclass gp2 storageclass.kubernetes.io/is-default-class- \
        --overwrite 2>/dev/null || true

      rm -f /tmp/kubeconfig-gp2-unset
    EOT
  }

  depends_on = [kubernetes_storage_class_v1.gp3]
}
