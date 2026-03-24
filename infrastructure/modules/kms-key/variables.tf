variable "alias_name" {
  description = "The display name of the key alias (without the alias/ prefix)"
  type        = string
}

variable "description" {
  description = "The description of the KMS key"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "deletion_window_in_days" {
  description = "Duration in days after which the key is deleted after destruction (7-30)"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "additional_key_admins" {
  description = "List of IAM principal ARNs that should have key administration permissions"
  type        = list(string)
  default     = []
}

variable "additional_key_users" {
  description = "List of IAM principal ARNs that should have key usage permissions"
  type        = list(string)
  default     = []
}

variable "enable_key_rotation" {
  description = "Whether to enable annual automatic key rotation"
  type        = bool
  default     = true
}

variable "multi_region" {
  description = "Whether to create a multi-region key"
  type        = bool
  default     = false
}
