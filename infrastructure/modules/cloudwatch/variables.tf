variable "service_name" {
  description = "The name of the service to monitor"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "log_group_names" {
  description = "List of CloudWatch log group names to include in the dashboard"
  type        = list(string)
  default     = []
}

variable "ecs_cluster_name" {
  description = "The name of the ECS cluster to monitor"
  type        = string
  default     = ""
}

variable "ecs_service_names" {
  description = "List of ECS service names to monitor"
  type        = list(string)
  default     = []
}

variable "alb_arn_suffix" {
  description = "The ARN suffix of the ALB to monitor"
  type        = string
  default     = ""
}

variable "rds_cluster_identifier" {
  description = "The RDS cluster identifier to monitor"
  type        = string
  default     = ""
}

variable "sqs_queue_names" {
  description = "List of SQS queue names to monitor"
  type        = list(string)
  default     = []
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN to send alarm notifications"
  type        = string
  default     = ""
}

variable "error_threshold" {
  description = "Number of errors to trigger the error rate alarm"
  type        = number
  default     = 10
}

variable "latency_threshold_ms" {
  description = "ALB response time threshold in milliseconds to trigger latency alarm"
  type        = number
  default     = 2000
}

variable "cpu_threshold_percent" {
  description = "ECS CPU utilization threshold percentage to trigger alarm"
  type        = number
  default     = 80
}

variable "memory_threshold_percent" {
  description = "ECS memory utilization threshold percentage to trigger alarm"
  type        = number
  default     = 80
}

variable "log_metric_filters" {
  description = "List of log metric filter configurations"
  type = list(object({
    name            = string
    log_group_name  = string
    filter_pattern  = string
    metric_name     = string
    metric_namespace = string
    metric_value    = string
  }))
  default = []
}
