data "terraform_remote_state" "ec2" {
  backend = "s3"
  config = {
    bucket         = "mikey-com-terraformstate"
    use_lockfile   = true
    key            = "RKE-cluster_dev/ec2"
    region         = "us-east-1"
  }
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
  
}