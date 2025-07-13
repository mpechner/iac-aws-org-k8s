data "aws_route53_zone" "main" {
  name         = "foobar.support."
  private_zone = false
}