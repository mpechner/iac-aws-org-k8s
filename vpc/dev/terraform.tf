terraform {
  required_version = ">= 1.5"
  # REQUIRED: Set bucket, region, dynamodb_table for your environment (cannot use variables in backend block). See repo README § Terraform state backend.
  backend "s3" {
    bucket         = "mikey-com-terraformstate"
    dynamodb_table = "terraform-state"
    key            = "vpc/dev"
    region         = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
