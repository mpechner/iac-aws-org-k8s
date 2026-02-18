
data "aws_availability_zones" "available" {}

locals {
  name   = var.name
  region = var.region

  vpc_cidr = var.vpc_cidr
  azs      = var.azs

  tags = {
    Example    = var.name
    GithubRepo = "terraform-aws-vpc"
    GithubOrg  = "terraform-aws-modules"
    ManagedBy = "terraform"
  }
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.name
  cidr = var.vpc_cidr

  azs                 = var.azs
  private_subnets     = var.private_subnets
  public_subnets      = var.public_subnets
  database_subnets    = var.db_subnets 
  elasticache_subnets = []
  redshift_subnets    = []
  intra_subnets       = []

  # Disable auto-assign public IP on private subnets
  map_public_ip_on_launch = false

  private_subnet_names = var.private_subnet_names
  public_subnet_names  = var.public_subnet_names
  database_subnet_names    = var.db_subnet_names
  elasticache_subnet_names = []
  redshift_subnet_names    = []
  intra_subnet_names       = []

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # Required for AWS Load Balancer Controller (NLB) subnet discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  customer_gateways = {}

  enable_vpn_gateway = false

  enable_dhcp_options              = true
  #dhcp_options_domain_name         = "ec2.internal"

  # VPC Flow Logs (Cloudwatch log group and IAM role will be created)
  vpc_flow_log_iam_role_name            = "vpc-flow-role"
  vpc_flow_log_iam_role_use_name_prefix = false
  enable_flow_log                       = true
  create_flow_log_cloudwatch_log_group  = true
  create_flow_log_cloudwatch_iam_role   = true
  flow_log_max_aggregation_interval     = 60

  tags = local.tags
}

################################################################################
# VPC Endpoints Module
################################################################################

module "vpc_endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
      tags            = { Name = "${local.name}-s3-gateway-endpoint" }
    }
  }

  tags = merge(local.tags, {
    Endpoint = "true"
  })
}

# Placeholder module (keeping for compatibility)
module "vpc_endpoints_nocreate" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"

  create = false
}

################################################################################
# Supporting Resources
################################################################################

#data "aws_iam_policy_document" "dynamodb_endpoint_policy" {
#  statement {
#    effect    = "Deny"
#    actions   = ["dynamodb:*"]
#    resources = ["*"]
#
#    principals {
#      type        = "*"
#      identifiers = ["*"]
#    }
#
#    condition {
#      test     = "StringNotEquals"
#      variable = "aws:sourceVpc"
#
#      values = [module.vpc.vpc_id]
#    }
#  }
#}
#
#data "aws_iam_policy_document" "generic_endpoint_policy" {
#  statement {
#    effect    = "Deny"
#    actions   = ["*"]
#    resources = ["*"]
#
#    principals {
#      type        = "*"
#      identifiers = ["*"]
#    }
#
#    condition {
#      test     = "StringNotEquals"
#      variable = "aws:SourceVpc"
#
#      values = [module.vpc.vpc_id]
#    }
#  }
#}
#
#resource "aws_security_group" "rds" {
#  name_prefix = "${local.name}-rds"
#  description = "Allow PostgreSQL inbound traffic"
#  vpc_id      = module.vpc.vpc_id
#
#  ingress {
#    description = "TLS from VPC"
#    from_port   = 5432
#    to_port     = 5432
#    protocol    = "tcp"
#    cidr_blocks = [module.vpc.vpc_cidr_block]
#  }
#
#  tags = local.tags
#}