# OpenVPN prod environment - Terraform config and backend

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "mikey-com-terraformstate"
    key            = "openvpn/prodvpn/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-west-2"

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/terraform-execute"
  }

  default_tags {
    tags = {
      Project     = "OpenVPN"
      Environment = "prod"
      ManagedBy   = "Terraform"
      Purpose     = "VPN Server"
    }
  }
}
