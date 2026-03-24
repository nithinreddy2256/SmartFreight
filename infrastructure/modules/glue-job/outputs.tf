output "job_name" {
  description = "The name of the Glue job"
  value       = aws_glue_job.this.name
}

output "job_arn" {
  description = "The ARN of the Glue job"
  value       = aws_glue_job.this.arn
}

output "role_arn" {
  description = "The ARN of the IAM role used by the Glue job"
  value       = aws_iam_role.glue.arn
}

output "role_name" {
  description = "The name of the IAM role used by the Glue job"
  value       = aws_iam_role.glue.name
}

output "connection_name" {
  description = "The name of the Glue JDBC connection"
  value       = local.use_connection ? aws_glue_connection.aurora[0].name : ""
}

output "security_configuration_name" {
  description = "The name of the Glue security configuration"
  value       = local.use_kms ? aws_glue_security_configuration.this[0].name : ""
}

output "log_group_name" {
  description = "The name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.glue.name
}
