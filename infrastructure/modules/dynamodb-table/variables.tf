variable "table_name" {
  description = "The name of the DynamoDB table"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "hash_key" {
  description = "The attribute name for the hash (partition) key"
  type        = string
}

variable "range_key" {
  description = "The attribute name for the range (sort) key (optional)"
  type        = string
  default     = ""
}

variable "attributes" {
  description = "List of attribute definitions. Each must have 'name' and 'type' (S, N, or B)"
  type = list(object({
    name = string
    type = string
  }))
}

variable "global_secondary_indexes" {
  description = "List of GSI definitions"
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = string
    non_key_attributes = optional(list(string))
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  default = []
}

variable "ttl_attribute" {
  description = "The name of the TTL attribute (leave empty to disable TTL)"
  type        = string
  default     = ""
}

variable "stream_enabled" {
  description = "Whether to enable DynamoDB Streams"
  type        = bool
  default     = false
}

variable "stream_view_type" {
  description = "The type of information written to the stream (NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES, KEYS_ONLY)"
  type        = string
  default     = "NEW_AND_OLD_IMAGES"
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key for server-side encryption"
  type        = string
  default     = ""
}

variable "billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "read_capacity" {
  description = "The number of read units for the table (used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "The number of write units for the table (used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "point_in_time_recovery_enabled" {
  description = "Whether to enable Point-in-Time Recovery"
  type        = bool
  default     = true
}
