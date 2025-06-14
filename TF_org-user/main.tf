# dev
provider "aws" {
  alias  = "dev"
  region = "us-west-1"
  assume_role {
    role_arn = "arn:aws:iam::REDACTED_ACCOUNT_ID:role/OrganizationAccountAccessRole"
  }
}

module "terraform_execute_dev1" {
  source = "./modules/terraform_execute_role"
  providers = {
    aws = aws.dev
  }
}
#mgmt
provider "aws" {
  alias  = "mgmt"
  region = "us-west-1"
  assume_role {
    role_arn = "arn:aws:iam::111416589270:role/OrganizationAccountAccessRole"
  }
}

module "terraform_execute_mgmt" {
  source = "./modules/terraform_execute_role"
  providers = {
    aws = aws.mgmt
  }
}

# network
provider "aws" {
  alias  = "network"
  region = "us-west-1"
  assume_role {
    role_arn = "arn:aws:iam::061154959995:role/OrganizationAccountAccessRole"
  }
}

module "terraform_execute_network" {
  source = "./modules/terraform_execute_role"
  providers = {
    aws = aws.network
  }
}

# prod
provider "aws" {
  alias  = "prod"
  region = "us-west-1"
  assume_role {
    role_arn = "arn:aws:iam::972553824779:role/OrganizationAccountAccessRole"
  }
}

module "terraform_execute_prod" {
  source = "./modules/terraform_execute_role"
  providers = {
    aws = aws.prod
  }
}