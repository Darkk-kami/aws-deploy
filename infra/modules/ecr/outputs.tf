output "repository_name" {
  description = "Name of the ECR repository."
  value       = aws_ecr_repository.main.name
}

output "repository_url" {
  description = "URL of the ECR repository, suitable for tagging and pushing images."
  value       = aws_ecr_repository.main.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository."
  value       = aws_ecr_repository.main.arn
}

output "registry_id" {
  description = "AWS account ID that owns the ECR registry."
  value       = aws_ecr_repository.main.registry_id
}

output "image_tag_mutability" {
  description = "Image tag mutability configured for the repository."
  value       = aws_ecr_repository.main.image_tag_mutability
}
