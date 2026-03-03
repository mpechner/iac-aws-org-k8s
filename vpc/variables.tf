# Account and role for VPC deployment (terraform-execute created by TF_org-user)
variable "account_id" {
  description = "AWS account ID where VPC is deployed (terraform-execute role must exist)"
  type        = string
}
