output "topic_arn" {
  description = "The ARN of the SNS topic"
  value       = aws_sns_topic.this.arn
}

output "topic_id" {
  description = "The ID of the SNS topic (same as ARN)"
  value       = aws_sns_topic.this.id
}

output "topic_name" {
  description = "The name of the SNS topic"
  value       = aws_sns_topic.this.name
}

output "dlq_arn" {
  description = "The ARN of the SNS dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "The URL of the SNS dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_name" {
  description = "The name of the SNS dead letter queue"
  value       = aws_sqs_queue.dlq.name
}

output "dlq_depth_alarm_arn" {
  description = "The ARN of the DLQ depth CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.dlq_depth.arn
}
