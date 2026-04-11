terraform {
  required_version = ">= 1.3"
  # REQUIRED: Set bucket, region, dynamodb_table for your environment (cannot use variables in backend block). See repo README § Terraform state backend.
  backend "s3" {
    bucket         = "mikey-com-terraformstate"
    dynamodb_table = "terraform-state"
    key            = "route53-prod-delegate"
    region         = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "prod_account_id" {
  type        = string
  description = "AWS account ID for the prod account"
}

variable "network_account_id" {
  type        = string
  description = "AWS account ID for the network/Route53 parent zone account"
}

variable "parent_zone_name" {
  type        = string
  description = "Parent Route53 zone name (e.g. foobar.support)"
  default     = "foobar.support"
}

variable "subdomain" {
  type        = string
  description = "Subdomain to delegate (e.g. prod.foobar.support)"
  default     = "prod.foobar.support"
}

provider "aws" {
  alias  = "network"
  region = "us-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${var.network_account_id}:role/terraform-execute"
  }
}

provider "aws" {
  alias  = "prod"
  region = "us-west-2"
  assume_role {
    role_arn = "arn:aws:iam::${var.prod_account_id}:role/terraform-execute"
  }
}

# 1. Create the delegated hosted zone in prod account
resource "aws_route53_zone" "prod_subdomain" {
  provider = aws.prod
  name     = var.subdomain
  comment  = "Delegated subdomain hosted zone in prod account"
}

# 2. Look up the parent zone in the network account
data "aws_route53_zone" "parent" {
  provider     = aws.network
  name         = "${var.parent_zone_name}."
  private_zone = false
}

# 3. Create NS delegation record in the parent zone
resource "aws_route53_record" "delegation_ns" {
  provider = aws.network
  zone_id  = data.aws_route53_zone.parent.zone_id
  name     = var.subdomain
  type     = "NS"
  ttl      = 300
  records  = aws_route53_zone.prod_subdomain.name_servers
}

output "zone_id" {
  description = "Route53 hosted zone ID for prod subdomain"
  value       = aws_route53_zone.prod_subdomain.zone_id
}

output "name_servers" {
  description = "Name servers for the prod subdomain zone"
  value       = aws_route53_zone.prod_subdomain.name_servers
}
