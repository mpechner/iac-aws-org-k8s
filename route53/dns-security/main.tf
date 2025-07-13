resource "aws_route53_record" "spf" {
   zone_id = data.aws_route53_zone.main.zone_id
  name    = "foobar.support"
  type    = "TXT"
  ttl     = 3600
  records = [
    "v=spf1 -all"
  ]
}

resource "aws_route53_record" "dmarc" {
  zone_id = data.aws_route53_zone.main.zone_id 
  name    = "_dmarc.foobar.support"
  type    = "TXT"
  ttl     = 3600
  records = [
    "v=DMARC1; p=reject; rua=mailto:aws-feedback@mikey.com"
  ]
}

#resource "aws_route53_record" "dkim" {
#  zone_id = data.aws_route53_zone.main.zone_id
#  name    = "myselector._domainkey.foobar.support"
#  type    = "TXT"
#  ttl     = 3600
#  records = [
#    "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9...IDAQAB"
#  ]
#}

resource "aws_route53_record" "caa" {
  zone_id = data.aws_route53_zone.main.zone_id 
  name    = "foobar.support"
  type    = "CAA"
  ttl     = 3600
  records = [
    "0 issue \"letsencrypt.org\"",
    "0 issuewild \";\""
  ]
}
