output "service_logging_bucket" {
  description = "Service logging bucket details"
  value = {
    id   = module.service_logging_bucket.bucket_id
    arn  = module.service_logging_bucket.bucket_arn
  }
}

output "rke_etcd_backups_bucket" {
  description = "RKE etcd backups bucket details"
  value = {
    id   = module.rke_etcd_backups.bucket_id
    arn  = module.rke_etcd_backups.bucket_arn
  }
}
