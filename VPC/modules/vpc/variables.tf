variable "region"{
    type = string
}

variable "name" {
    description =  "vpc badse name"
    type = string
}
variable "vpc_cidr"{
    type = string
}

variable "azs"{
    type = list(string)
}

variable "enable_nat_gateway"{
    default = true
}

variable "single_nat_gateway" {
    default = true
}




#
# subnets 
#
variable "private_subnets" {
    type = list(string)
}

variable "private_subnet_names" {
    type = list(string)
}


variable "public_subnets" {
    type = list(string)
}

variable "public_subnet_names" {
    type = list(string)
}


variable "db_subnets" {
    type = list(string)
}

variable "db_subnet_names" {
    type = list(string)
}

# -----------------------------------------------------------------------------
# VPC Endpoints (Lambda / private subnet access without NAT)
# Set enable_vpc_endpoints = true and pass allowed_source_sg_ids (e.g. Lambda SG).
# -----------------------------------------------------------------------------
variable "enable_vpc_endpoints" {
  description = "Create interface + DynamoDB gateway endpoints for private subnet access (no NAT). S3 gateway already exists."
  type        = bool
  default     = false
}

variable "endpoint_subnet_ids" {
  description = "Subnet IDs for interface endpoints; defaults to private subnets when empty."
  type        = list(string)
  default     = []
}

variable "private_route_table_ids" {
  description = "Route table IDs for DynamoDB gateway endpoint; defaults to VPC private route tables when empty."
  type        = list(string)
  default     = []
}

variable "allowed_source_sg_ids" {
  description = "Security group IDs allowed to reach interface endpoints (e.g. Lambda SG). If empty, private subnet CIDRs are used."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags merged with module tags for endpoints and endpoint security group."
  type        = map(string)
  default     = {}
}

variable "vpc_endpoint_services_interface" {
  description = "Interface endpoint service names (short form, e.g. ecr.api). Default: ECR, Secrets Manager, KMS, Logs, SSM trio, STS, Lambda. Add events if Lambda manages EventBridge."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "secretsmanager", "kms", "logs", "ssm", "ssmmessages", "ec2messages", "sts", "lambda"]
}

variable "vpc_endpoint_services_gateway" {
  description = "Gateway endpoint service names. Default: dynamodb only (S3 already exists in this module)."
  type        = list(string)
  default     = ["dynamodb"]
}

variable "flow_log_group_name" {
  description = "Override the CloudWatch log group name for VPC flow logs. Defaults to the name the terraform-aws-vpc module creates: /aws/vpc-flow-log/{vpc_id}."
  type        = string
  default     = ""
}