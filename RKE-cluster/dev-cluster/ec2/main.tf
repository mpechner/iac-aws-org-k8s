module "rke-nodes" {
  source      = "../../modules/ec2"
  ec2_ssh_key = aws_key_pair.rke_ssh.key_name
  subnet_ids  = data.aws_subnets.node_subnets.ids

  agent_hostnames     = local.agent_hostnames
  agent_ami           = data.aws_ami.ubuntu_2204.id
  agent_instance_type = "t3a.large"

  server_hostnames     = local.server_hostnames
  server_ami           = data.aws_ami.ubuntu_2204.id
  server_instance_type = "t3a.large"

  aws_region = var.aws_region

  # Scope the Route53 ChangeResourceRecordSets permission to these zones only.
  # Covers cert-manager DNS-01 (vpn zone) and external-dns (cluster zone).
  route53_hosted_zone_ids = var.route53_hosted_zone_ids

  # Scope Secrets Manager write to the openvpn cert publisher path.
  openvpn_secret_prefix = "openvpn/"
}
