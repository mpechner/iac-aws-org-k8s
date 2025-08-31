terraform {
  required_version = ">= 1.3"
  
  backend "s3" {
    bucket = "mikey-com-terraformstate"
    dynamodb_table = "terraform-state"
    key    = "RKE-cluster_dev/rke"
    region = "us-east-1"
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

locals {
    dev_account     = "REDACTED_ACCOUNT_ID"
}

provider "aws" {
  #alias  = "dev"
  region = "us-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${local.dev_account}:role/terraform-execute"
  }
}

# Kubernetes provider configuration
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}