data "aws_vpc" "current" {
  filter {
    name   = "tag:Name"
    values = ["dev"]
  }
}

data "aws_subnets" "node_subnets" {
  filter {
    name   = "tag:Name"
    values = local.node_subnet_names
  }
}

data "aws_subnets" "rke_subnets" {
  filter {
    name   = "tag:Name"
    values = local.rke_subnet_names
  }
}

# Get individual subnet details for node subnets
data "aws_subnet" "node_subnet_details" {
  count = length(local.node_subnet_names)
  id    = data.aws_subnets.node_subnets.ids[count.index]
}

# Get individual subnet details for RKE subnets
data "aws_subnet" "rke_subnet_details" {
  count = length(local.rke_subnet_names)
  id    = data.aws_subnets.rke_subnets.ids[count.index]
}

data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}