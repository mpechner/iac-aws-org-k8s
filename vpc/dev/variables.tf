variable account_id {
    default = "iREDACTED_ACCOUNT_ID"
}

variable region {
    default = "us-west-1"
}



variable     name {
    default = "dev"
}
variable     vpc_cidr {
    default = "10.8.0.0/16"
}
variable     azs {
    default = [ "us-west-1a","us-west-1b","us-west-1c" ]
}
variable     private_subnets {
    default = ["10.8.1.0/20", "10.8.33.0/20", "10.8.65.0/20"]
}
variable     private_subnet_names {
    default = [ "dev-priv-us-west-1a", "dev-priv-us-west-1b", "dev-priv-us-west-1c" ]
}
    
variable     public_subnets {
    default = ["10.8.0.0/24", "10.8.32.0/24", "10.8.64.0/24"]
}
variable     public_subnet_names {
    default = [ "dev-pub-us-west-1a", "dev-pub-us-west-1b", "dev-pub-us-west-1c" ]
}
    
variable     db_subnets {
    default = ["10.8.17.0/26", "10.8.49.0/26", "10.8.96.0/26"]
}
variable     db_subnet_names {
    default = [ "dev-db-us-west-1a", "dev-db-us-west-1b", "dev-db-us-west-1c" ]
}
    