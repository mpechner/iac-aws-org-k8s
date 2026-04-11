provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/terraform-execute"
  }

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Stage       = "2-applications"
    }
  }
}

# EKS exec-based auth — no kubeconfig file needed.
# cluster_endpoint and cluster_ca_cert come from 1-infrastructure outputs (which reads from 2-cluster).
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks_cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks_cluster.outputs.cluster_ca_cert)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", var.cluster_name,
      "--region", var.aws_region,
      "--role-arn", "arn:aws:iam::${var.account_id}:role/terraform-execute",
    ]
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.terraform_remote_state.eks_cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks_cluster.outputs.cluster_ca_cert)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", var.cluster_name,
        "--region", var.aws_region,
        "--role-arn", "arn:aws:iam::${var.account_id}:role/terraform-execute",
      ]
    }
  }
}
