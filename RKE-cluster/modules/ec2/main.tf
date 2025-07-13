
resource "aws_instance" "server_rke_nodes" {
  for_each = { for idx, name in var.server_hostnames : name => {
    hostname = name
    subnet_id = var.subnet_ids[idx % length(var.subnet_ids)]
  }}

  ami           = var.server_ami
  instance_type = var.server_instance_type
  subnet_id     = each.value.subnet_id
  key_name      = var.ec2_ssh_key

  tags = {
    Name = each.key
  }

  user_data = templatefile("${path.module}/config/userdata.sh", {
    PLAYBOOK_REPO = var.ansible_repo
    PLAYBOOK_FILE = var.ansible_playbook
  })
}

resource "aws_instance" "agent_rke_nodes" {
  for_each = { for idx, name in var.agent_hostnames : name => {
    hostname = name
    subnet_id = var.subnet_ids[idx % length(var.subnet_ids)]
  }}

  ami           = var.agent_ami
  instance_type = var.agent_instance_type
  subnet_id     = each.value.subnet_id
  key_name      = var.ec2_ssh_key

  tags = {
    Name = each.key
  }

  user_data = templatefile("${path.module}/config/userdata.sh", {
    PLAYBOOK_REPO = var.ansible_repo
    PLAYBOOK_FILE = var.ansible_playbook
  })
}