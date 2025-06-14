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

variable "enable_nat_gateway"{
    default = true
}

variable "single_nat_gateway" {
    default = true
}