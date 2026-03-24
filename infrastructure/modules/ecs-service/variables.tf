variable "service_name" {
  description = "The name of the ECS service"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "cluster_arn" {
  description = "The ARN of the ECS cluster to deploy the service into"
  type        = string
}

variable "image_uri" {
  description = "The Docker image URI (including tag) for the container"
  type        = string
}

variable "cpu" {
  description = "The number of CPU units for the task definition"
  type        = number
  default     = 256
}

variable "memory" {
  description = "The amount of memory (in MiB) for the task definition"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "The desired number of ECS service instances"
  type        = number
  default     = 1
}

variable "alb_target_group_arn" {
  description = "The ARN of the ALB target group for load balancing"
  type        = string
  default     = ""
}

variable "container_port" {
  description = "The port on the container to associate with the load balancer"
  type        = number
  default     = 8080
}

variable "environment_vars" {
  description = "Map of environment variable names to values for the container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of secret names to their ARNs in Secrets Manager or Parameter Store"
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "List of subnet IDs where the ECS tasks will be deployed"
  type        = list(string)
}

variable "security_group_id" {
  description = "The security group ID to assign to the ECS tasks"
  type        = string
}

variable "min_capacity" {
  description = "Minimum number of tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto-scaling"
  type        = number
  default     = 10
}

variable "cpu_scale_up_threshold" {
  description = "CPU utilization percentage to trigger scale-up"
  type        = number
  default     = 70
}

variable "sqs_queue_arn" {
  description = "ARN of SQS queue to use for queue-depth auto-scaling (optional)"
  type        = string
  default     = ""
}

variable "sqs_queue_name" {
  description = "Name of SQS queue to use for queue-depth auto-scaling (optional)"
  type        = string
  default     = ""
}

variable "sqs_scale_up_threshold" {
  description = "Number of SQS messages per task to trigger scale-up"
  type        = number
  default     = 100
}

variable "task_role_policy_arns" {
  description = "List of additional IAM policy ARNs to attach to the task role"
  type        = list(string)
  default     = []
}

variable "health_check_path" {
  description = "Path for the ALB health check"
  type        = string
  default     = "/health"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}
