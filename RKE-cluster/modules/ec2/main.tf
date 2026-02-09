
resource "aws_security_group" "nodes" {
  name_prefix = "rke-nodes-"
  vpc_id      = local.vpc_id_resolved

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_resolved]
  }

  # Kubernetes API (RKE2 server)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_resolved, "172.27.224.0/20"]
  }

  # RKE2 supervisor port
  ingress {
    from_port   = 9345
    to_port     = 9345
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_resolved]
  }

  # etcd client port (for RKE2 HA)
  ingress {
    from_port   = 2379
    to_port     = 2379
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_resolved]
  }

  # etcd peer port (for RKE2 HA)
  ingress {
    from_port   = 2380
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_resolved]
  }

  # VXLAN overlay (Canal/Calico)
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
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

resource "aws_iam_role_policy" "secretsmanager_access" {
  count = var.instance_profile_name == "" ? 1 : 0
  name  = "rke-nodes-secretsmanager-access"
  role  = aws_iam_role.nodes[0].id
  policy = file("${path.module}/policies/secretsmanager-access-policy.json")
}

resource "aws_iam_instance_profile" "nodes" {
  count = var.instance_profile_name == "" ? 1 : 0
  name  = "rke-nodes-profile"
  role  = aws_iam_role.nodes[0].name
}

# Wait for all server instances to pass status checks
resource "null_resource" "wait_for_servers" {
  for_each = aws_instance.server_rke_nodes

  triggers = {
    instance_id = each.value.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for server instance ${each.key} (${each.value.id}) to pass status checks..."
      
      # Assume the terraform-execute role
      TEMP_CREDS=$(aws sts assume-role \
        --role-arn "arn:aws:iam::REDACTED_ACCOUNT_ID:role/terraform-execute" \
        --role-session-name "tf-ec2-health-check-server" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text)
      
      export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | awk '{print $3}')
      
      for i in $(seq 1 60); do
        STATUS=$(aws ec2 describe-instance-status \
          --region us-west-2 \
          --instance-ids ${each.value.id} \
          --include-all-instances \
          --query 'InstanceStatuses[0].[InstanceStatus.Status,SystemStatus.Status]' \
          --output text 2>/dev/null || echo "initializing initializing")
        
        INSTANCE_STATUS=$(echo $STATUS | awk '{print $1}')
        SYSTEM_STATUS=$(echo $STATUS | awk '{print $2}')
        
        if [ "$INSTANCE_STATUS" = "ok" ] && [ "$SYSTEM_STATUS" = "ok" ]; then
          echo "SUCCESS: ${each.key} passed all status checks!"
          exit 0
        fi
        
        echo "Progress: ${each.key} - Instance: $INSTANCE_STATUS, System: $SYSTEM_STATUS (attempt $i/60)"
        sleep 15
      done
      
      echo "TIMEOUT: ${each.key} did not pass status checks within 15 minutes"
      exit 1
    EOT
  }

  depends_on = [aws_instance.server_rke_nodes]
}

# Wait for all agent instances to pass status checks
resource "null_resource" "wait_for_agents" {
  for_each = aws_instance.agent_rke_nodes

  triggers = {
    instance_id = each.value.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for agent instance ${each.key} (${each.value.id}) to pass status checks..."
      
      # Assume the terraform-execute role
      TEMP_CREDS=$(aws sts assume-role \
        --role-arn "arn:aws:iam::REDACTED_ACCOUNT_ID:role/terraform-execute" \
        --role-session-name "tf-ec2-health-check-agent" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text)
      
      export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | awk '{print $3}')
      
      for i in $(seq 1 60); do
        STATUS=$(aws ec2 describe-instance-status \
          --region us-west-2 \
          --instance-ids ${each.value.id} \
          --include-all-instances \
          --query 'InstanceStatuses[0].[InstanceStatus.Status,SystemStatus.Status]' \
          --output text 2>/dev/null || echo "initializing initializing")
        
        INSTANCE_STATUS=$(echo $STATUS | awk '{print $1}')
        SYSTEM_STATUS=$(echo $STATUS | awk '{print $2}')
        
        if [ "$INSTANCE_STATUS" = "ok" ] && [ "$SYSTEM_STATUS" = "ok" ]; then
          echo "SUCCESS: ${each.key} passed all status checks!"
          exit 0
        fi
        
        echo "Progress: ${each.key} - Instance: $INSTANCE_STATUS, System: $SYSTEM_STATUS (attempt $i/60)"
        sleep 15
      done
      
      echo "TIMEOUT: ${each.key} did not pass status checks within 15 minutes"
      exit 1
    EOT
  }

  depends_on = [aws_instance.agent_rke_nodes]
}