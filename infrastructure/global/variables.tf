variable "aws_region" {
  description = "The primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "public_domain" {
  description = "The public domain name for SmartFreight (e.g., smartfreight.com)"
  type        = string
  default     = "smartfreight.com"
}

variable "private_domain" {
  description = "The private internal domain name (e.g., smartfreight.internal)"
  type        = string
  default     = "smartfreight.internal"
}

variable "allowed_account_ids" {
  description = "List of AWS account IDs allowed to pull ECR images and assume the CI/CD role"
  type        = list(string)
  default     = []
}

variable "vpc_ids" {
  description = "List of VPC IDs to associate with the private hosted zone"
  type        = list(string)
  default     = []
}

variable "dev_alb_dns_name" {
  description = "DNS name of the dev environment ALB (for Route53 records)"
  type        = string
  default     = ""
}

variable "test_alb_dns_name" {
  description = "DNS name of the test environment ALB (for Route53 records)"
  type        = string
  default     = ""
}

variable "prod_alb_dns_name" {
  description = "DNS name of the prod environment ALB (for Route53 records)"
  type        = string
  default     = ""
}
