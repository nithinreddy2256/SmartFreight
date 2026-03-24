variable "api_name" {
  description = "The name of the API Gateway HTTP API"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "lambda_arn" {
  description = "The ARN of the Lambda function to integrate with"
  type        = string
}

variable "lambda_invoke_arn" {
  description = "The invoke ARN of the Lambda function"
  type        = string
}

variable "cognito_user_pool_arn" {
  description = "The ARN of the Cognito User Pool for JWT authorizer (optional)"
  type        = string
  default     = ""
}

variable "cognito_user_pool_client_id" {
  description = "The Cognito User Pool Client ID for the authorizer"
  type        = string
  default     = ""
}

variable "stage_name" {
  description = "The name of the API Gateway stage"
  type        = string
  default     = "$default"
}

variable "auto_deploy" {
  description = "Whether changes to the API should be automatically deployed"
  type        = bool
  default     = true
}

variable "throttling_burst_limit" {
  description = "The throttling burst limit for the default route"
  type        = number
  default     = 500
}

variable "throttling_rate_limit" {
  description = "The throttling rate limit for the default route"
  type        = number
  default     = 1000
}

variable "cors_allow_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "cors_allow_headers" {
  description = "List of allowed headers for CORS"
  type        = list(string)
  default     = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key"]
}

variable "log_retention_days" {
  description = "Number of days to retain API Gateway access logs"
  type        = number
  default     = 30
}
