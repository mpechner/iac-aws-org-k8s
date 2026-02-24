# OpenVPN Server - reusable module
# Creates security group, EC2 instance, and Elastic IP

locals {
  common_tags = merge(var.tags, {
    Name        = "${var.environment}-openvpn-server"
    Environment = var.environment
    Purpose     = "OpenVPN Server"
  })
}

# Security Group for OpenVPN
resource "aws_security_group" "openvpn" {
  name        = "${var.environment}-openvpn-sg"
  description = "Security group for OpenVPN server"
  vpc_id      = var.vpc_id

  # SSH access from admin CIDR
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
    description = "SSH access from admin IP"
  }

  # OpenVPN port
  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "OpenVPN UDP port"
  }

  # OpenVPN Admin Web Interface (HTTPS)
  ingress {
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
    description = "OpenVPN Admin Web Interface (HTTPS)"
  }

  # OpenVPN Admin Web Interface (HTTP redirect)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
    description = "OpenVPN Admin Web Interface (HTTP redirect)"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-openvpn-sg" })
}

# EC2 Instance for OpenVPN
resource "aws_instance" "openvpn" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.openvpn.id]
  key_name               = var.key_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/userdata.sh", {
    environment = var.environment
  })

  tags = local.common_tags

  depends_on = [aws_security_group.openvpn]
}

# Elastic IP for persistent public IP
resource "aws_eip" "openvpn" {
  instance = aws_instance.openvpn.id
  domain   = "vpc"

  tags = merge(local.common_tags, { Name = "${var.environment}-openvpn-eip" })
}

# Route53 A record: vpn.<domain_name> (e.g. vpn.dev.foobar.support). Hostname is always "vpn".
resource "aws_route53_record" "vpn" {
  count           = var.route53_zone_id != "" && var.domain_name != "" ? 1 : 0
  zone_id         = var.route53_zone_id
  name            = "vpn"
  type            = "A"
  ttl             = 300
  records         = [aws_eip.openvpn.public_ip]
  allow_overwrite = true
}
