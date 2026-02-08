# OpenVPN Server Infrastructure
# This creates an EC2 instance and supporting resources for OpenVPN

# AMI provided via variable

# Automatically detect your current public IP address
data "http" "my_ip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  my_ip = chomp(data.http.my_ip.response_body)
  # Use detected IP if comcast_ip is not provided, otherwise use comcast_ip
  admin_ip = var.comcast_ip != "" ? var.comcast_ip : "${local.my_ip}/32"
}

# Get VPC outputs from the VPC module state
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "mikey-com-terraformstate"
    key    = "Network"
    region = "us-east-1"
  }
}

# Get subnet ID - use specified subnet or first PUBLIC subnet from VPC
locals {
  subnet_id = var.subnet_id != "" ? var.subnet_id : data.terraform_remote_state.vpc.outputs.public_subnets[0]
}

# Reference existing VPC resources from the VPC module
data "aws_subnet" "selected" {
  id = local.subnet_id
}

data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

# Security Group for OpenVPN
resource "aws_security_group" "openvpn" {
  name        = "${var.environment}-openvpn-sg"
  description = "Security group for OpenVPN server"
  vpc_id      = data.aws_vpc.selected.id

  # SSH access from your IP (auto-detected or specified)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.admin_ip]
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
    cidr_blocks = [local.admin_ip]
    description = "OpenVPN Admin Web Interface (HTTPS)"
  }

  # Note: Client UI also served on 943

  # OpenVPN Admin Web Interface (HTTP redirect)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.admin_ip]
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

  tags = {
    Name        = "${var.environment}-openvpn-sg"
    Environment = var.environment
    Purpose     = "OpenVPN Server"
  }
}

# EC2 Instance for OpenVPN
resource "aws_instance" "openvpn" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.openvpn.id]
  key_name               = aws_key_pair.openvpn_ssh.key_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/userdata.sh", {
    environment = var.environment
    domain      = var.domain
  })

  tags = {
    Name        = "${var.environment}-openvpn-server"
    Environment = var.environment
    Purpose     = "OpenVPN Server"
  }

  # Ensure instance is fully ready
  depends_on = [aws_security_group.openvpn]
}

# Elastic IP for persistent public IP
resource "aws_eip" "openvpn" {
  instance = aws_instance.openvpn.id
  domain   = "vpc"

  tags = {
    Name        = "${var.environment}-openvpn-eip"
    Environment = var.environment
    Purpose     = "OpenVPN Server"
  }
}

# Route53 record (optional - if you have a domain)
resource "aws_route53_record" "openvpn" {
  count   = var.create_dns_record ? 1 : 0
  zone_id = var.route53_zone_id
  name    = "vpn.${var.domain}"
  type    = "A"
  ttl     = "300"
  records = [aws_eip.openvpn.public_ip]
}
