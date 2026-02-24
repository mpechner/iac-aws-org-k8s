variable "aws_region" {
  default = "us-west-2"
}

variable "route53_hosted_zone_ids" {
  type        = list(string)
  description = "Route53 hosted zone IDs the node role may modify. Typically the cluster domain zone + the VPN domain zone."
  default     = ["Z06437531SIUA7T3WCKTM"]
}
