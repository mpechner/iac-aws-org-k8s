module "dev" {
    source = "../modules/vpc"
    region = var.region
    name = var.name
    vpc_cidr = var.vpc_cidr
    azs = var.azs
    private_subnets = var.private_subnets
    private_subnet_names = var.private_subnet_names
    public_subnets = var.public_subnets
    public_subnet_names = var.public_subnet_names
    db_subnets = var.db_subnets
    db_subnet_names = var.db_subnet_names

}