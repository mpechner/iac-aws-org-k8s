data "terraform_remote_state" "ec2" {
  backend = "s3"
  config = {
    bucket         = "mikey-com-terraformstate"
    use_lockfile   = true
    key            = "RKE-cluster_dev/ec2"
    region         = "us-east-1"
  }
}

resource "random_password" "rke2_token" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "rke2_token" {
  name = "${local.cluster_name}-rke2-token"
}

resource "aws_secretsmanager_secret_version" "rke2_token" {
  secret_id     = aws_secretsmanager_secret.rke2_token.id
  secret_string = random_password.rke2_token.result
}

module "rke-server"{
  source= "../../modules/server"
  cluster_name = local.cluster_name
  vpc_id = data.aws_vpc.current.id
  subnet_ids = data.aws_subnets.node_subnets.ids
  key_name = data.terraform_remote_state.ec2.outputs.rke_ssh_key_name
  ssh_cidr_blocks = local.node_subnet_cidrs
  cluster_cidr_blocks = local.rke_subnet_cidrs
  aws_region = var.aws_region
  server_instance_ips = data.terraform_remote_state.ec2.outputs.server_instance_private_ips
  ansible_user = "ubuntu"
  ansible_ssh_private_key_file = "~/.ssh/rke-key"
  
  # Enable etcd backups to S3
  etcd_backup_enabled = true
  etcd_backup_bucket  = "mikey-dev-rke-etcd-backups"
  
  depends_on = [aws_secretsmanager_secret_version.rke2_token]

}

module "rke-agent" {
  source = "../../modules/agent"
  cluster_name = local.cluster_name
  vpc_id = data.aws_vpc.current.id
  subnet_ids = data.aws_subnets.node_subnets.ids
  key_name = data.terraform_remote_state.ec2.outputs.rke_ssh_key_name
  ssh_cidr_blocks = local.node_subnet_cidrs
  cluster_cidr_blocks = local.rke_subnet_cidrs
  aws_region = var.aws_region
  agent_instance_ips = data.terraform_remote_state.ec2.outputs.agent_instance_private_ips
  ansible_user = "ubuntu"
  ansible_ssh_private_key_file = "~/.ssh/rke-key"
  server_endpoint = element(data.terraform_remote_state.ec2.outputs.server_instance_private_ips, 0)
  depends_on = [aws_secretsmanager_secret_version.rke2_token, module.rke-server]

}