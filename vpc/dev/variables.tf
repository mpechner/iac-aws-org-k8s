variable account_id {
    description = "AWS account ID"
    type        = string
}

variable region {
    default = "us-west-2"
}

variable environment{
    default = "dev"
}

variable     name {
    default = "dev"
}
variable     vpc_cidr {
    default = "10.8.0.0/16"
}
variable     azs {
    default = [ "us-west-2a","us-west-2b","us-west-2c" ]
}
variable     private_subnets {
    default = ["10.8.16.0/20", "10.8.80.0/20", "10.8.144.0/20", 
    "10.8.192.0/20", "10.8.208.0/20", "10.8.224.0/20"]
}
variable     private_subnet_names {
    default = [ "dev-priv-us-west-2a", "dev-priv-us-west-2b", "dev-priv-us-west-2c",
    "dev-rke-us-west-2a", "dev-rke-us-west-2b", "dev-rke-us-west-2c"  ]
}
    
variable     public_subnets {
    default = ["10.8.0.0/24", "10.8.64.0/24", "10.8.128.0/24"]
}
variable     public_subnet_names {
    default = [ "dev-pub-us-west-2a", "dev-pub-us-west-2b", "dev-pub-us-west-2c" ]
}
    
variable     db_subnets {
    default = ["10.8.32.0/26", "10.8.96.0/26", "10.8.160.0/26"]
}
variable     db_subnet_names {
    default = [ "dev-db-us-west-2a", "dev-db-us-west-2b", "dev-db-us-west-2c" ]
}

# VPC endpoints (Lambda / private subnet access without NAT)
variable "enable_vpc_endpoints" {
  description = "Create interface + DynamoDB gateway endpoints for private subnet access."
  type        = bool
  default     = true
}
variable "endpoint_subnet_ids" {
  description = "Subnet IDs for interface endpoints; default empty = use private subnets."
  type        = list(string)
  default     = []
}
variable "private_route_table_ids" {
  description = "Route table IDs for DynamoDB gateway; default empty = use VPC private route tables."
  type        = list(string)
  default     = []
}
variable "allowed_source_sg_ids" {
  description = "Security group IDs allowed to reach interface endpoints (e.g. Lambda SG)."
  type        = list(string)
  default     = []
}
variable "tags" {
  description = "Tags merged with module tags for endpoints."
  type        = map(string)
  default     = {}
}
variable "vpc_endpoint_services_interface" {
  description = "Interface endpoint services (e.g. ecr.api, logs, lambda). Add events if Lambda manages EventBridge."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "ssm", "ssmmessages", "ec2messages", "sts"]
}
variable "vpc_endpoint_services_gateway" {
  description = "Gateway endpoint services. Default dynamodb only (S3 already exists)."
  type        = list(string)
  default     = ["dynamodb"]
}
variable "enable_nat_gateway" {
  type    = bool
  default = true
}
variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "alert_email" {
  description = "Email for VPC flow log alerts. Leave empty to skip email subscription."
  type        = string
  default     = ""
}
