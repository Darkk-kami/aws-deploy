data "aws_region" "current" {}

data "aws_availability_zones" "available_azs" {
  state = "available"
}