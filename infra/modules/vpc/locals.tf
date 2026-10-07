locals {
  name_prefix   = "${var.tags.Tier}-${var.tags.ProductName}" # e.g. prod-app
  effective_azs = min(var.desired_azs, length(data.aws_availability_zones.available_azs.names))
  az_list       = slice(data.aws_availability_zones.available_azs.names, 0, local.effective_azs)

  # AZ for each subnet, round-robin across az_list
  public_azs  = [for i in range(length(var.lb_subnet_cidrs)) : local.az_list[i % length(local.az_list)]]
  private_azs = [for i in range(length(var.app_subnet_cidrs)) : local.az_list[i % length(local.az_list)]]

  # List of interface endpoints to create, based on enabled_vpc_endpoints variable
  supported_endpoint_services = concat(["ecr.api", "ecr.dkr", "s3", "logs"])
  unsupported_endpoints       = setsubtract(toset(var.enabled_vpc_endpoints), toset(local.supported_endpoint_services))
}