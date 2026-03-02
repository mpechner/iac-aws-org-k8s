variable "aws_region" {
  default = "us-west-2"
}

# EC2 remote state (used by data.terraform_remote_state.ec2; set to your state bucket if different)
variable "ec2_state_bucket" {
  description = "S3 bucket containing the RKE EC2 Terraform state"
  type        = string
  default     = "mikey-com-terraformstate"
}

variable "ec2_state_key" {
  description = "S3 object key for the RKE EC2 state"
  type        = string
  default     = "RKE-cluster_dev/ec2"
}

variable "ec2_state_region" {
  description = "AWS region where the EC2 state bucket lives"
  type        = string
  default     = "us-east-1"
}