# OpenVPN dev environment - VPC lookup and module invocation

# Detect admin IP when not provided
data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  my_ip     = chomp(data.http.my_ip.response_body)
  admin_ip  = var.comcast_ip != "" ? var.comcast_ip : "${local.my_ip}/32"
  subnet_id = var.subnet_id != "" ? var.subnet_id : data.terraform_remote_state.vpc.outputs.public_subnets[0]
  vpc_id    = var.vpc_id != "" ? var.vpc_id : data.terraform_remote_state.vpc.outputs.vpc_id
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.vpc_state_bucket
    key    = var.vpc_state_key
    region = var.vpc_state_region
  }
}

module "openvpn" {
  source = "../module"

  environment      = var.environment
  vpc_id           = local.vpc_id
  subnet_id        = local.subnet_id
  ami_id           = var.ami_id
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size
  admin_cidr       = local.admin_ip
  key_name         = aws_key_pair.openvpn_ssh.key_name
  ssh_username     = var.ssh_username

  route53_zone_id = var.route53_zone_id
  domain_name     = var.domain_name
}
