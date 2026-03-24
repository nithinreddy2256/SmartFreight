output "service_id" {
  description = "The ID of the ECS service"
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "The ARN of the task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "The family of the task definition"
  value       = aws_ecs_task_definition.this.family
}

output "task_execution_role_arn" {
  description = "The ARN of the task execution IAM role"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "The ARN of the task IAM role"
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "The name of the task IAM role"
  value       = aws_iam_role.task.name
}

output "security_group_id" {
  description = "The ID of the ECS service security group"
  value       = aws_security_group.service.id
}

output "log_group_name" {
  description = "The name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.service.name
}

output "log_group_arn" {
  description = "The ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.service.arn
}

output "autoscaling_target_resource_id" {
  description = "The resource ID for the auto-scaling target"
  value       = aws_appautoscaling_target.ecs.resource_id
}
