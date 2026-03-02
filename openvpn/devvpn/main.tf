# OpenVPN dev environment - VPC lookup and module invocation

# Detect admin IP when not provided
data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  my_ip              = chomp(data.http.my_ip.response_body)
  admin_ip           = var.comcast_ip != "" ? var.comcast_ip : "${local.my_ip}/32"
  subnet_id          = var.subnet_id != "" ? var.subnet_id : data.terraform_remote_state.vpc.outputs.public_subnets[0]
  vpc_id             = var.vpc_id != "" ? var.vpc_id : data.terraform_remote_state.vpc.outputs.vpc_id
}

# Look up the VPC endpoint security group by name pattern
data "aws_security_groups" "vpc_endpoints" {
  filter {
    name   = "group-name"
    values = ["${var.environment}-vpc-endpoints*"]
  }
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
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

  enable_tls_sync = var.enable_tls_sync
  tls_secret_name = var.tls_secret_name
}

# Allow OpenVPN security group to reach VPC interface endpoints (Secrets Manager, STS, etc.)
# This is needed for the TLS sync script to access AWS services via VPC endpoints
resource "aws_security_group_rule" "openvpn_to_vpc_endpoints" {
  count = length(data.aws_security_groups.vpc_endpoints.ids) > 0 ? 1 : 0

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = module.openvpn.openvpn_security_group_id
  security_group_id        = data.aws_security_groups.vpc_endpoints.ids[0]
  description              = "Allow OpenVPN server to reach VPC interface endpoints (Secrets Manager, STS)"
}

# Run Ansible playbook to install TLS certificate sync cronjob (after SSH key is written to disk)
resource "null_resource" "openvpn_tls_sync" {
  count = var.enable_tls_sync ? 1 : 0

  triggers = {
    instance_id = module.openvpn.openvpn_server_id
    eip         = module.openvpn.openvpn_public_ip
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e

      VPN_FQDN="${var.domain_name != "" ? "vpn.${var.domain_name}" : module.openvpn.openvpn_public_ip}"
      TLS_SECRET_NAME="${var.tls_secret_name}"
      SSH_KEY="${local_file.openvpn_ssh_private_key.filename}"
      ANSIBLE_SCRIPT="${path.module}/../ansible/setup-tls-sync.sh"

      echo "🔧 Running Ansible to install TLS sync on OpenVPN server: $VPN_FQDN"
      echo "   SSH Key: $SSH_KEY"

      # Check if SSH key exists
      if [ ! -f "$SSH_KEY" ]; then
        echo "⚠️ SSH key not found at $SSH_KEY"
        echo "   TLS sync will not be installed automatically."
        echo "   Run manually: cd openvpn/ansible && ./setup-tls-sync.sh"
        exit 0
      fi

      # Check if Ansible script exists
      if [ ! -f "$ANSIBLE_SCRIPT" ]; then
        echo "⚠️ Ansible script not found at $ANSIBLE_SCRIPT"
        echo "   TLS sync will not be installed automatically."
        echo "   Run manually: cd openvpn/ansible && ./setup-tls-sync.sh"
        exit 0
      fi

      # Wait for instance to be ready
      echo "⏳ Waiting for OpenVPN server to be ready..."
      sleep 30

      # Run Ansible setup with auto-approve to skip interactive prompts
      cd "$(dirname "$ANSIBLE_SCRIPT")"
      export SSH_KEY
      AUTO_APPROVE=1 ./"$(basename "$ANSIBLE_SCRIPT")" || true
    EOT

    environment = {
      VPN_FQDN        = var.domain_name != "" ? "vpn.${var.domain_name}" : module.openvpn.openvpn_public_ip
      TLS_SECRET_NAME = var.tls_secret_name
      SSH_KEY         = local_file.openvpn_ssh_private_key.filename
      AUTO_APPROVE    = "1"
    }

    working_dir = path.module
  }

  depends_on = [
    module.openvpn,
    local_file.openvpn_ssh_private_key,
  ]

  lifecycle {
    create_before_destroy = true
  }
}
