variable "queue_name" {
  description = "The name of the SQS queue"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "The visibility timeout for the queue in seconds"
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "The number of seconds Amazon SQS retains a message"
  type        = number
  default     = 345600 # 4 days
}

variable "max_receive_count" {
  description = "Number of times a message is received before being sent to the DLQ"
  type        = number
  default     = 3
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key for server-side encryption"
  type        = string
  default     = ""
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic to subscribe this queue to (optional)"
  type        = string
  default     = ""
}

variable "filter_policy" {
  description = "SNS subscription filter policy as a JSON string (optional)"
  type        = string
  default     = ""
}

variable "delay_seconds" {
  description = "The time in seconds that the delivery of all messages in the queue will be delayed"
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "The limit of how many bytes a message can contain"
  type        = number
  default     = 262144 # 256 KB
}

variable "receive_wait_time_seconds" {
  description = "The time for which a ReceiveMessage call will wait for a message to arrive (long polling)"
  type        = number
  default     = 20
}

variable "dlq_message_retention_seconds" {
  description = "The number of seconds to retain messages in the dead letter queue"
  type        = number
  default     = 1209600 # 14 days
}

variable "fifo_queue" {
  description = "Whether to create a FIFO queue"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enables content-based deduplication for FIFO queues"
  type        = bool
  default     = false
}
