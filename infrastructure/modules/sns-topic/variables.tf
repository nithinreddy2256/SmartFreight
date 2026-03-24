variable "topic_name" {
  description = "The name of the SNS topic"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key for server-side encryption"
  type        = string
  default     = ""
}

variable "display_name" {
  description = "The display name for the SNS topic"
  type        = string
  default     = ""
}

variable "fifo_topic" {
  description = "Whether to create a FIFO topic"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enables content-based deduplication for FIFO topics"
  type        = bool
  default     = false
}

variable "allowed_publish_principals" {
  description = "List of IAM principal ARNs allowed to publish to this topic"
  type        = list(string)
  default     = []
}
