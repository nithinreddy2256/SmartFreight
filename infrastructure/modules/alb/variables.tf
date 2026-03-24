variable "alb_name" {
  description = "The name of the Application Load Balancer"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "internal" {
  description = "Whether the ALB should be internal (true) or external/internet-facing (false)"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "The VPC ID where the ALB will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ALB"
  type        = list(string)
}

variable "certificate_arn" {
  description = "The ARN of the ACM SSL/TLS certificate for HTTPS"
  type        = string
  default     = ""
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  type        = string
  default     = ""
}

variable "access_logs_prefix" {
  description = "S3 prefix for ALB access logs"
  type        = string
  default     = "alb-logs"
}

variable "idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle"
  type        = number
  default     = 60
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to connect to the ALB (for external ALBs)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "target_groups" {
  description = "Map of target group configurations"
  type = map(object({
    port              = number
    protocol          = string
    target_type       = string
    health_check_path = string
    health_check_port = optional(string)
  }))
  default = {}
}
