variable "environment" {
  description = "The deployment environment"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "The AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "cognito_callback_urls" {
  description = "Callback URLs for Cognito"
  type        = list(string)
  default     = ["https://app.smartfreight.com/callback"]
}

variable "cognito_domain_prefix" {
  description = "Cognito hosted UI domain prefix"
  type        = string
  default     = "smartfreight-prod"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener"
  type        = string
}

variable "aurora_instance_class" {
  description = "Instance class for Aurora provisioned instances"
  type        = string
  default     = "db.r6g.large"
}

variable "aurora_instance_count" {
  description = "Number of Aurora instances (writer + readers)"
  type        = number
  default     = 2
}

variable "aurora_glue_username" {
  description = "Aurora username for Glue JDBC connections — sourced from Secrets Manager"
  type        = string
  sensitive   = true
}

variable "aurora_glue_password" {
  description = "Aurora password for Glue JDBC connections — sourced from Secrets Manager"
  type        = string
  sensitive   = true
}
