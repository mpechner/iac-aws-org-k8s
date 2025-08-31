
resource "aws_security_group" "nodes" {
  name_prefix = "rke-nodes-"
  vpc_id      = local.vpc_id_resolved

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_resolved]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_resolved]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "server_rke_nodes" {
  for_each = { for idx, name in var.server_hostnames : name => {
    hostname = name
    subnet_id = var.subnet_ids[idx % length(var.subnet_ids)]
  }}

  ami           = var.server_ami
  instance_type = var.server_instance_type
  subnet_id     = each.value.subnet_id
  key_name      = var.ec2_ssh_key
  iam_instance_profile = var.instance_profile_name != "" ? var.instance_profile_name : aws_iam_instance_profile.nodes[0].name
  vpc_security_group_ids = [aws_security_group.nodes.id]

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
  iam_instance_profile = var.instance_profile_name != "" ? var.instance_profile_name : aws_iam_instance_profile.nodes[0].name
  vpc_security_group_ids = [aws_security_group.nodes.id]

  tags = {
    Name = each.key
  }

  user_data = templatefile("${path.module}/config/userdata.sh", {
    PLAYBOOK_REPO = var.ansible_repo
    PLAYBOOK_FILE = var.ansible_playbook
  })
}

# Conditional IAM role + instance profile for nodes (SSM + optional ECR pull)
resource "aws_iam_role" "nodes" {
  count = var.instance_profile_name == "" ? 1 : 0

  name = "rke-nodes-role"
  assume_role_policy = file("${path.module}/policies/ec2-trust-policy.json")
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.instance_profile_name == "" ? 1 : 0
  role       = aws_iam_role.nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ecr_pull" {
  count = var.instance_profile_name == "" && var.create_ecr_pull_policy ? 1 : 0
  name  = "rke-nodes-ecr-pull"
  role  = aws_iam_role.nodes[0].id
  policy = file("${path.module}/policies/ecr-pull-policy.json")
}

resource "aws_iam_role_policy" "ec2_describe" {
  count = var.instance_profile_name == "" ? 1 : 0
  name  = "rke-nodes-ec2-describe"
  role  = aws_iam_role.nodes[0].id
  policy = file("${path.module}/policies/ec2-describe-policy.json")
}

resource "aws_iam_instance_profile" "nodes" {
  count = var.instance_profile_name == "" ? 1 : 0
  name  = "rke-nodes-profile"
  role  = aws_iam_role.nodes[0].name
}