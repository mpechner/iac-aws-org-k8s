data "aws_subnet" "first" {
  id = element(var.subnet_ids, 0)
}

locals {
  vpc_id_resolved  = var.vpc_id  != "" ? var.vpc_id  : data.aws_subnet.first.vpc_id
}

data "aws_vpc" "selected" {
  id = local.vpc_id_resolved
}

locals {
  vpc_cidr_resolved = var.vpc_cidr != "" ? var.vpc_cidr : data.aws_vpc.selected.cidr_block
}