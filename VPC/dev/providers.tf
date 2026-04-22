
provider "aws" {
  region = var.region

    assume_role {
    role_arn     = "arn:aws:iam::${var.account_id}:role/terraform-execute"
    session_name = "terraform"
  }

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"

    }
  }
}