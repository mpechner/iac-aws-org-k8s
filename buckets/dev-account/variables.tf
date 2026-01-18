variable "account_id" {
  type    = string
  default = "REDACTED_ACCOUNT_ID"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_assume_role_arn" {
  type    = string
  default = "arn:aws:iam::REDACTED_ACCOUNT_ID:role/terraform-execute"
}
