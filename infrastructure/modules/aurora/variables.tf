variable "cluster_identifier" {
  description = "The identifier for the Aurora cluster"
  type        = string
}

variable "database_name" {
  description = "The name of the initial database"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID where the Aurora cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Aurora DB subnet group"
  type        = list(string)
}

variable "serverless" {
  description = "Whether to use Aurora Serverless v2 (true) or provisioned instances (false)"
  type        = bool
  default     = true
}

variable "min_acu" {
  description = "Minimum ACU capacity for Aurora Serverless v2"
  type        = number
  default     = 0.5
}

variable "max_acu" {
  description = "Maximum ACU capacity for Aurora Serverless v2"
  type        = number
  default     = 4.0
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on the cluster"
  type        = bool
  default     = true
}

variable "instance_class" {
  description = "The instance class for provisioned Aurora instances"
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = "Number of provisioned Aurora instances (used when serverless = false)"
  type        = number
  default     = 2
}

variable "backup_retention_period" {
  description = "The number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "preferred_backup_window" {
  description = "The daily time range during which automated backups are performed"
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "The weekly time range during which system maintenance can occur"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to connect to the database"
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key for encryption at rest"
  type        = string
  default     = ""
}
