output "dashboard_arn" {
  description = "The ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.this.dashboard_arn
}

output "dashboard_name" {
  description = "The name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "ecs_cpu_alarm_arns" {
  description = "List of ARNs for ECS CPU alarms"
  value       = aws_cloudwatch_metric_alarm.ecs_cpu[*].arn
}

output "ecs_memory_alarm_arns" {
  description = "List of ARNs for ECS memory alarms"
  value       = aws_cloudwatch_metric_alarm.ecs_memory[*].arn
}

output "alb_latency_alarm_arn" {
  description = "The ARN of the ALB latency alarm"
  value       = local.monitor_alb ? aws_cloudwatch_metric_alarm.alb_latency[0].arn : ""
}

output "alb_5xx_alarm_arn" {
  description = "The ARN of the ALB 5xx error rate alarm"
  value       = local.monitor_alb ? aws_cloudwatch_metric_alarm.alb_5xx[0].arn : ""
}

output "rds_cpu_alarm_arn" {
  description = "The ARN of the RDS CPU alarm"
  value       = local.monitor_rds ? aws_cloudwatch_metric_alarm.rds_cpu[0].arn : ""
}

output "composite_alarm_arn" {
  description = "The ARN of the composite service health alarm"
  value       = (local.monitor_ecs && local.monitor_alb) ? aws_cloudwatch_composite_alarm.service_health[0].arn : ""
}

output "error_metric_filter_name" {
  description = "The name of the error rate log metric filter"
  value       = length(var.log_group_names) > 0 ? aws_cloudwatch_log_metric_filter.error_rate[0].name : ""
}
