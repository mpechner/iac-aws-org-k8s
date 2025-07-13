terraform {
  required_version = ">= 1.3"
  
  backend "s3" {
    bucket = "mikey-com-terraformstate"
    dynamodb_table = "terraform-state"
    key    = "route53-dns-security"
    region = "us-east-1"
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
    dev_account     = "REDACTED_ACCOUNT_ID"
    network_account = "061154959995"
}

provider "aws" {
  #alias  = "network"
  region = "us-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${local.network_account}:role/terraform-execute"
  }
}

provider "aws" {
  alias  = "dev"
  region = "us-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${local.dev_account}:role/terraform-execute"
  }
}