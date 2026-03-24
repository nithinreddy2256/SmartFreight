variable "job_name" {
  description = "The name of the Glue job"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "script_s3_location" {
  description = "The S3 path where the PySpark script is stored (s3://bucket/path/script.py)"
  type        = string
}

variable "aurora_connection_string" {
  description = "JDBC connection string for Aurora PostgreSQL"
  type        = string
  default     = ""
}

variable "max_capacity" {
  description = "The maximum number of AWS Glue data processing units (DPUs) allocated for this job"
  type        = number
  default     = 2.0
}

variable "glue_version" {
  description = "The version of Glue to use for this job"
  type        = string
  default     = "4.0"
}

variable "python_version" {
  description = "The Python version to use (2 or 3)"
  type        = string
  default     = "3"
}

variable "max_retries" {
  description = "The maximum number of times to retry this job if it fails"
  type        = number
  default     = 1
}

variable "timeout" {
  description = "The job timeout in minutes"
  type        = number
  default     = 60
}

variable "default_arguments" {
  description = "Map of default arguments for this job"
  type        = map(string)
  default     = {}
}

variable "worker_type" {
  description = "The type of predefined worker that is allocated when a job runs (Standard, G.1X, G.2X)"
  type        = string
  default     = "G.1X"
}

variable "number_of_workers" {
  description = "The number of workers that are allocated when a job runs"
  type        = number
  default     = 2
}

variable "use_worker_type" {
  description = "Whether to use worker type and number_of_workers instead of max_capacity"
  type        = bool
  default     = true
}

variable "s3_temp_bucket" {
  description = "S3 bucket for Glue temporary files"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID for the Glue connection"
  type        = string
  default     = ""
}

variable "security_group_id" {
  description = "Security group ID for the Glue connection"
  type        = string
  default     = ""
}

variable "availability_zone" {
  description = "Availability zone for the Glue connection"
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting Glue job bookmarks and logs"
  type        = string
  default     = ""
}
