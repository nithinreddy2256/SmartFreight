output "key_id" {
  description = "The globally unique identifier for the KMS key"
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "The Amazon Resource Name (ARN) of the KMS key"
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "The display name of the KMS key alias"
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "The Amazon Resource Name (ARN) of the KMS key alias"
  value       = aws_kms_alias.this.arn
}

output "deletion_alarm_arn" {
  description = "The ARN of the CloudWatch alarm for key deletion events"
  value       = aws_cloudwatch_metric_alarm.key_deletion.arn
}
