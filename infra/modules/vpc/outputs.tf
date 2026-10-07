output "vpc_id" {
  description = "ID of the application VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block associated with the application VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, in the configured subnet order."
  value       = aws_subnet.lb_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private application subnets, in the configured subnet order."
  value       = aws_subnet.app_subnets[*].id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway, or null when internet gateway creation is disabled."
  value       = try(aws_internet_gateway.main[0].id, null)
}

output "public_route_table_id" {
  description = "ID of the route table associated with public subnets."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the route table associated with private application subnets."
  value       = aws_route_table.private.id
}

output "vpc_endpoint_ids" {
  description = "VPC endpoint IDs keyed by service name."
  value       = { for service, endpoint in aws_vpc_endpoint.interface_endpoints : service => endpoint.id }
}

output "vpc_endpoint_security_group_id" {
  description = "ID of the security group attached to interface VPC endpoints."
  value       = aws_security_group.vpc_endpoints_sg.id
}