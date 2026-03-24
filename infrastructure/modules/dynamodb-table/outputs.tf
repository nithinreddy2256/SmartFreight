output "table_id" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.this.id
}

output "table_arn" {
  description = "The ARN of the DynamoDB table"
  value       = aws_dynamodb_table.this.arn
}

output "table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.this.name
}

output "table_stream_arn" {
  description = "The ARN of the DynamoDB Streams (empty if not enabled)"
  value       = aws_dynamodb_table.this.stream_arn
}

output "table_stream_label" {
  description = "A timestamp that provides a starting point for the stream (empty if not enabled)"
  value       = aws_dynamodb_table.this.stream_label
}

output "hash_key" {
  description = "The hash key of the DynamoDB table"
  value       = aws_dynamodb_table.this.hash_key
}

output "range_key" {
  description = "The range key of the DynamoDB table"
  value       = aws_dynamodb_table.this.range_key
}
