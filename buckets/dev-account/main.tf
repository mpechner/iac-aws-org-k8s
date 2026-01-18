locals {
  account_id = var.account_id
  region     = var.aws_region
}

# Service logging bucket (created first, no logging on itself)
module "service_logging_bucket" {
  source = "../modules/s3-bucket"

  bucket_name = "mikey-s3-servicelogging-dev-us-west-2"
  region      = local.region
  account_id  = local.account_id

  versioning_enabled                 = false
  lifecycle_expiration_days          = 90
  lifecycle_noncurrent_expiration_days = 90

  enable_logging = false

  tags = {
    Name        = "mikey-s3-servicelogging-dev-us-west-2"
    Purpose     = "S3 Access Logs"
    Environment = var.environment
  }
}

# Bucket policy to allow S3 to write logs
resource "aws_s3_bucket_policy" "service_logging" {
  bucket = module.service_logging_bucket.bucket_id

  policy = templatefile("${path.module}/policies/s3-logging-policy.json.tftpl", {
    bucket_arn = module.service_logging_bucket.bucket_arn
    account_id = local.account_id
  })

  depends_on = [module.service_logging_bucket]
}

# etcd backups bucket
module "rke_etcd_backups" {
  source = "../modules/s3-bucket"

  bucket_name = "mikey-dev-rke-etcd-backups"
  region      = local.region
  account_id  = local.account_id

  versioning_enabled                 = true
  lifecycle_expiration_days          = 365
  lifecycle_noncurrent_expiration_days = 365

  enable_logging = true
  logging_bucket = module.service_logging_bucket.bucket_id
  logging_prefix = "${local.account_id}/${local.region}/mikey-dev-rke-etcd-backups/"

  tags = {
    Name        = "mikey-dev-rke-etcd-backups"
    Purpose     = "RKE etcd Backups"
    Environment = var.environment
  }

  depends_on = [aws_s3_bucket_policy.service_logging]
}
