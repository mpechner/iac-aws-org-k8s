# OpenVPN Server - reusable module
# Creates security group, EC2 instance, and Elastic IP

data "aws_region" "current" {}

data "aws_ami" "openvpn" {
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = ["OpenVPN Access Server Community Image*"]
  }
}

data "aws_kms_key" "ebs_default" {
  key_id = "alias/aws/ebs"
}

locals {
  common_tags = merge(var.tags, {
    Name        = "${var.environment}-openvpn-server"
    Environment = var.environment
    Purpose     = "OpenVPN Server"
  })
  ebs_kms_key_id = var.kms_key_arn != "" ? var.kms_key_arn : data.aws_kms_key.ebs_default.arn
}

# IAM Role for OpenVPN Server - allows reading TLS certificate from Secrets Manager
resource "aws_iam_role" "openvpn" {
  name = "${var.environment}-openvpn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-openvpn-role" })
}

resource "aws_iam_instance_profile" "openvpn" {
  name = "${var.environment}-openvpn-profile"
  role = aws_iam_role.openvpn.name

  tags = merge(local.common_tags, { Name = "${var.environment}-openvpn-profile" })
}

resource "aws_iam_role_policy" "openvpn_secrets" {
  name = "${var.environment}-openvpn-secrets-policy"
  role = aws_iam_role.openvpn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "ReadSecrets"
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue",
            "secretsmanager:DescribeSecret"
          ]
          Resource = [
            "arn:aws:secretsmanager:*:*:secret:${var.tls_secret_name}-*",
            "arn:aws:secretsmanager:*:*:secret:openvpn/*"
          ]
        },
        {
          # ListSecrets cannot be scoped to a resource — AWS requires Resource = "*" for List operations.
          Sid      = "ListSecrets"
          Effect   = "Allow"
          Action   = ["secretsmanager:ListSecrets"]
          Resource = "*"
        },
        {
          # Secrets Manager always uses KMS for envelope encryption — either the AWS-managed key
          # (aws/secretsmanager) or a CMK.  kms:Decrypt is always required.
          # The kms:ViaService condition locks this to calls originating from Secrets Manager
          # in this region only — no other KMS usage is permitted even though Resource = "*".
          # When var.kms_key_arn is provided the resource is narrowed to that single key ARN.
          Sid    = "DecryptSecretsManagerEnvelope"
          Effect = "Allow"
          Action = ["kms:Decrypt"]
          Resource = var.kms_key_arn != "" ? var.kms_key_arn : "*"
          Condition = {
            StringEquals = {
              "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
            }
          }
        }
      ],
      # GenerateDataKey is only needed when the instance writes a secret (cert publisher).
      # Scope to CMK if provided; fall back to * with ViaService condition otherwise.
      var.enable_tls_sync ? [
        {
          Sid    = "GenerateDataKeyForWrite"
          Effect = "Allow"
          Action = ["kms:GenerateDataKey"]
          Resource = var.kms_key_arn != "" ? var.kms_key_arn : "*"
          Condition = {
            StringEquals = {
              "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
            }
          }
        }
      ] : []
    )
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
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.openvpn.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.openvpn.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.openvpn.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = local.ebs_kms_key_id
  }

  # Require IMDSv2 for security (disables IMDSv1)
  # hop_limit=2 allows pods to use IMDSv2 via instance profile
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
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
