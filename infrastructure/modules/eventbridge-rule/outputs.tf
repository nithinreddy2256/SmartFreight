output "rule_id" {
  description = "The ID of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.this.id
}

output "rule_arn" {
  description = "The ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.this.arn
}

output "rule_name" {
  description = "The name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.this.name
}

output "target_id" {
  description = "The ID of the EventBridge target"
  value       = aws_cloudwatch_event_target.this.target_id
}

output "iam_role_arn" {
  description = "The ARN of the IAM role used by EventBridge"
  value       = aws_iam_role.eventbridge.arn
}

output "iam_role_name" {
  description = "The name of the IAM role used by EventBridge"
  value       = aws_iam_role.eventbridge.name
}
