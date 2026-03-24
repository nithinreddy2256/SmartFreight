output "repository_id" {
  description = "The registry ID where the repository was created"
  value       = aws_ecr_repository.this.registry_id
}

output "repository_arn" {
  description = "The ARN of the ECR repository"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "The name of the ECR repository"
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "The URL of the ECR repository (used for docker push/pull)"
  value       = aws_ecr_repository.this.repository_url
}

output "registry_id" {
  description = "The registry ID (AWS account ID) of the ECR registry"
  value       = aws_ecr_repository.this.registry_id
}
