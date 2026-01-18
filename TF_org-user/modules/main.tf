t add terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_iam_role" "terraform_execute" {
  name = "terraform-execute"
  assume_role_policy = templatefile("${path.module}/policies/terraform-assume-role-policy.json.tftpl", {
    principal_arn = "arn:aws:iam::REDACTED_ACCOUNT_ID:root"
  })
}

resource "aws_iam_role_policy_attachment" "admin_access" {
  role       = aws_iam_role.terraform_execute.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
