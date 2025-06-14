
provider "aws" {
  alias  = "primary"
  region = "us-west-1"

}

terraform {
  backend "s3" {
    bucket = "mikey-com-terraformstate"
    dynamodb_table = "terraform-state"
    key    = "Network"
    region = "us-east-1"
  }
}