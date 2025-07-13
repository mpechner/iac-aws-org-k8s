module "rks-nodes" {
  source      = "../modules/ec2"
  ec2_ssh_key = aws_key_pair.rke_ssh.key_name
  subnet_ids = data.aws_subnets.node_subnets.ids
  agent_hostnames = local.agent_hostnames
  agent_ami = data.aws_ami.ubuntu_2204.id
  agent_instance_type = "t3a.small"

  server_hostnames = local.server_hostnames
  server_ami = data.aws_ami.ubuntu_2204.id
  server_instance_type = "t3a.small"
}