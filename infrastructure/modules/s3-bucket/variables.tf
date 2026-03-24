variable "bucket_name" {
  description = "The name of the S3 bucket"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "versioning_enabled" {
  description = "Whether to enable S3 versioning"
  type        = bool
  default     = true
}

variable "lifecycle_expiration_days" {
  description = "Number of days after which non-current versions expire (0 = disabled)"
  type        = number
  default     = 90
}

variable "lifecycle_transition_days" {
  description = "Number of days before transitioning current objects to STANDARD_IA"
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key for server-side encryption"
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "Whether to force destroy the bucket even if it contains objects"
  type        = bool
  default     = false
}

variable "access_log_bucket" {
  description = "The name of the bucket to use for access logging (leave empty to disable)"
  type        = string
  default     = ""
}

variable "access_log_prefix" {
  description = "The prefix for access log objects"
  type        = string
  default     = "access-logs/"
}

variable "allowed_principals" {
  description = "List of IAM principal ARNs allowed to access this bucket"
  type        = list(string)
  default     = []
}

variable "cors_rules" {
  description = "List of CORS rules for the bucket"
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = list(string)
    max_age_seconds = number
  }))
  default = []
}
