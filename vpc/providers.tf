
provider "aws" {
  alias  = "primary"
  region = "us-west-1"
}

provider "aws" {
  alias  = "dr"
  region = "us-east-2"
}
terraform {
  backend "s3" {
    bucket = "mikey-com-terraformstate"
    dynamodb_table = "terraform-state"
    key    = "Network"
    region = "us-east-1"
  }
}