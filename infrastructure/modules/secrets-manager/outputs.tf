output "secret_id" {
  description = "The ID of the secret"
  value       = aws_secretsmanager_secret.this.id
}

output "secret_arn" {
  description = "The ARN of the secret"
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_name" {
  description = "The name of the secret"
  value       = aws_secretsmanager_secret.this.name
}

output "secret_version_id" {
  description = "The unique identifier of the version of the secret"
  value       = local.has_initial_value ? aws_secretsmanager_secret_version.this[0].version_id : ""
}

output "rotation_enabled" {
  description = "Whether automatic rotation is enabled for this secret"
  value       = local.use_rotation
}
