output "api_id" {
  description = "The ID of the API Gateway HTTP API"
  value       = aws_apigatewayv2_api.this.id
}

output "api_arn" {
  description = "The ARN of the API Gateway HTTP API"
  value       = aws_apigatewayv2_api.this.arn
}

output "api_endpoint" {
  description = "The URI of the API"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "stage_id" {
  description = "The ID of the API Gateway stage"
  value       = aws_apigatewayv2_stage.this.id
}

output "stage_invoke_url" {
  description = "The URL to invoke the API pointing to the stage"
  value       = aws_apigatewayv2_stage.this.invoke_url
}

output "execution_arn" {
  description = "The ARN prefix to be used in an aws_lambda_permission's source_arn"
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "authorizer_id" {
  description = "The ID of the Cognito authorizer (empty if not configured)"
  value       = local.use_authorizer ? aws_apigatewayv2_authorizer.cognito[0].id : ""
}

output "log_group_name" {
  description = "The name of the CloudWatch log group for API Gateway access logs"
  value       = aws_cloudwatch_log_group.api_gateway.name
}
