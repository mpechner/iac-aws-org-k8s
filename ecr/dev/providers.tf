# ECR - dev - AWS provider

provider "aws" {
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/terraform-execute"
  }

  default_tags {
    tags = {
      Project     = "ECR"
      Environment = "dev"
      ManagedBy   = "Terraform"
    }
  }
}
