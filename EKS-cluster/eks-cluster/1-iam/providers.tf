terraform {
  required_version = ">= 1.3"
  # REQUIRED: Set bucket, region, dynamodb_table for your environment (cannot use variables in backend block). See repo README § Terraform state backend.
  backend "s3" {
    bucket         = "mikey-com-terraformstate"
    dynamodb_table = "terraform-state"
    key            = "eks-dev/1-iam"
    region         = "us-east-1"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/terraform-execute"
  }

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Cluster     = var.cluster_name
    }
  }
}
