data "aws_acm_certificate" "issued" {
  domain   = var.domain_name
  statuses = ["ISSUED"]
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}