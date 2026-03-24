variable "rule_name" {
  description = "The name of the EventBridge rule"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "description" {
  description = "The description of the rule"
  type        = string
  default     = ""
}

variable "schedule_expression" {
  description = "The scheduling expression (e.g., rate(1 hour), cron(0 12 * * ? *)). Set to empty string to use event_pattern instead."
  type        = string
  default     = ""
}

variable "event_pattern" {
  description = "The event pattern as JSON string (for event-pattern rules). Set to empty string to use schedule_expression instead."
  type        = string
  default     = ""
}

variable "event_bus_name" {
  description = "The event bus to associate with the rule (default or custom bus name)"
  type        = string
  default     = "default"
}

variable "target_arn" {
  description = "The ARN of the target (Lambda, ECS task, SQS queue, etc.)"
  type        = string
}

variable "target_type" {
  description = "The type of the target (lambda, ecs, sqs)"
  type        = string

  validation {
    condition     = contains(["lambda", "ecs", "sqs"], var.target_type)
    error_message = "target_type must be one of: lambda, ecs, sqs"
  }
}

variable "target_input" {
  description = "Valid JSON string to pass to the target as the event (optional)"
  type        = string
  default     = ""
}

variable "target_input_transformer" {
  description = "Input transformer configuration for the target (optional)"
  type = object({
    input_paths    = map(string)
    input_template = string
  })
  default = null
}

# ECS-specific variables
variable "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster (required for ECS targets)"
  type        = string
  default     = ""
}

variable "ecs_task_definition_arn" {
  description = "The ARN of the ECS task definition (required for ECS targets)"
  type        = string
  default     = ""
}

variable "ecs_launch_type" {
  description = "The launch type for ECS tasks"
  type        = string
  default     = "FARGATE"
}

variable "ecs_subnet_ids" {
  description = "Subnet IDs for ECS tasks (required for ECS targets)"
  type        = list(string)
  default     = []
}

variable "ecs_security_group_ids" {
  description = "Security group IDs for ECS tasks"
  type        = list(string)
  default     = []
}

variable "ecs_assign_public_ip" {
  description = "Whether to assign a public IP to ECS tasks"
  type        = bool
  default     = false
}

variable "is_enabled" {
  description = "Whether the rule is enabled"
  type        = bool
  default     = true
}

variable "retry_policy_max_attempts" {
  description = "Maximum number of retry attempts"
  type        = number
  default     = 3
}

variable "dlq_arn" {
  description = "ARN of an SQS queue to use as a dead letter target"
  type        = string
  default     = ""
}
