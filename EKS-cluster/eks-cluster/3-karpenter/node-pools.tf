# ------------------------------------------------------------------------------
# EC2NodeClass
# Defines the AWS-specific configuration shared by both NodePools:
# which subnets/security groups to use, which AMI family, and node settings.
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "ec2_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
        - alias: al2023@latest
      instanceProfile: ${data.terraform_remote_state.iam.outputs.karpenter_node_instance_profile_name}

      # Select EKS subnets by cluster tag (set in 2-cluster)
      subnetSelectorTerms:
        - tags:
            kubernetes.io/cluster/${var.cluster_name}: shared
            Name: "dev-rke-*"

      # Select the node security group EKS creates for this cluster
      securityGroupSelectorTerms:
        - tags:
            kubernetes.io/cluster/${var.cluster_name}: owned

      # Enforce IMDSv2 on all Karpenter-launched nodes
      # hop limit = 1 so pods cannot reach the node's IMDS endpoint
      metadataOptions:
        httpTokens: required
        httpPutResponseHopLimit: 1
        httpEndpoint: enabled

      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 50Gi
            volumeType: gp3
            encrypted: true
            deleteOnTermination: true
  YAML

  depends_on = [helm_release.karpenter]
}

# ------------------------------------------------------------------------------
# NodePool: spot-interruptible
# General-purpose spot capacity. Consolidation and interruptions always allowed.
# Schedule workloads here with:
#   nodeSelector:
#     karpenter.sh/capacity-type: spot
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "nodepool_spot" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: spot-interruptible
    spec:
      template:
        metadata:
          labels:
            nodepool: spot-interruptible
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                - m5a.large
                - m5a.xlarge
          # Expire nodes periodically to keep them patched
          expireAfter: 24h

      limits:
        cpu: "16"
        memory: 64Gi

      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
        budgets:
          - nodes: "10%"
  YAML

  depends_on = [kubectl_manifest.ec2_node_class]
}

# ------------------------------------------------------------------------------
# NodePool: on-demand-stable
# On-demand capacity for workloads that must not be interrupted during
# business hours (Mon–Fri 07:00–19:00 UTC).
# Schedule workloads here with:
#   nodeSelector:
#     karpenter.sh/capacity-type: on-demand
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "nodepool_ondemand" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: on-demand-stable
    spec:
      template:
        metadata:
          labels:
            nodepool: on-demand-stable
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: node.kubernetes.io/instance-type
              operator: In
              values:
                - m5a.large
                - m5a.xlarge
          expireAfter: 168h  # weekly rotation

      limits:
        cpu: "16"
        memory: 64Gi

      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
        budgets:
          # Block ALL disruptions Mon–Fri 07:00–19:00 UTC
          - nodes: "0"
            schedule: "0 7 * * 1-5"
            duration: 12h
          - nodes: "10%"
  YAML

  depends_on = [kubectl_manifest.ec2_node_class]
}
