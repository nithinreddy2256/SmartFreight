output "user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "The ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_name" {
  description = "The name of the Cognito User Pool"
  value       = aws_cognito_user_pool.this.name
}

output "user_pool_endpoint" {
  description = "The endpoint of the Cognito User Pool"
  value       = aws_cognito_user_pool.this.endpoint
}

output "user_pool_domain" {
  description = "The Cognito hosted UI domain"
  value       = aws_cognito_user_pool_domain.this.domain
}

output "user_pool_domain_cloudfront_arn" {
  description = "The CloudFront distribution ARN for the hosted UI domain"
  value       = aws_cognito_user_pool_domain.this.cloudfront_distribution_arn
}

output "web_client_id" {
  description = "The ID of the web app client"
  value       = aws_cognito_user_pool_client.web.id
}

output "m2m_client_id" {
  description = "The ID of the M2M app client"
  value       = aws_cognito_user_pool_client.m2m.id
}

output "m2m_client_secret" {
  description = "The secret of the M2M app client"
  value       = aws_cognito_user_pool_client.m2m.client_secret
  sensitive   = true
}

output "resource_server_identifier" {
  description = "The identifier of the M2M resource server"
  value       = aws_cognito_resource_server.m2m.identifier
}
