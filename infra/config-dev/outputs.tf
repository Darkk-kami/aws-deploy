output "vpc_id" {
  description = "ID of the development application VPC."
  value       = module.app_network.vpc_id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the development application VPC."
  value       = module.app_network.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = module.app_network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private application subnets."
  value       = module.app_network.private_subnet_ids
}

output "internet_gateway_id" {
  description = "ID of the internet gateway, or null when it is disabled."
  value       = module.app_network.internet_gateway_id
}

output "public_route_table_id" {
  description = "ID of the public-subnet route table."
  value       = module.app_network.public_route_table_id
}

output "private_route_table_id" {
  description = "ID of the private-subnet route table."
  value       = module.app_network.private_route_table_id
}

output "vpc_endpoint_ids" {
  description = "Interface VPC endpoint IDs keyed by service name."
  value       = module.app_network.vpc_endpoint_ids
}

output "vpc_endpoint_security_group_id" {
  description = "ID of the security group attached to interface VPC endpoints."
  value       = module.app_network.vpc_endpoint_security_group_id
}

output "ecr_repository_name" {
  description = "Name of the application ECR repository."
  value       = module.app_repo.repository_name
}

output "ecr_repository_url" {
  description = "URL of the application ECR repository, suitable for tagging and pushing images."
  value       = module.app_repo.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the application ECR repository."
  value       = module.app_repo.repository_arn
}

output "ecr_registry_id" {
  description = "AWS account ID that owns the ECR registry."
  value       = module.app_repo.registry_id
}

output "ecr_image_tag_mutability" {
  description = "Image tag mutability configured for the application repository."
  value       = module.app_repo.image_tag_mutability
}

output "app_monitoring_dashboard_name" {
  description = "Name of the ECS application monitoring dashboard."
  value       = module.app_monitoring.dashboard_name
}

output "app_cpu_alarm_name" {
  description = "Name of the ECS application CPU utilization alarm."
  value       = module.app_monitoring.cpu_alarm_name
}

output "app_memory_alarm_name" {
  description = "Name of the ECS application memory utilization alarm."
  value       = module.app_monitoring.memory_alarm_name
}
