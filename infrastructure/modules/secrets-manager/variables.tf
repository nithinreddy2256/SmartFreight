variable "secret_name" {
  description = "The name of the secret in Secrets Manager"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "secret_string" {
  description = "The secret value to store (JSON string or plain text)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key to encrypt the secret"
  type        = string
  default     = ""
}

variable "rotation_lambda_arn" {
  description = "The ARN of the Lambda function to rotate the secret (optional)"
  type        = string
  default     = ""
}

variable "rotation_days" {
  description = "Number of days between automatic rotations"
  type        = number
  default     = 30
}

variable "description" {
  description = "A description of the secret"
  type        = string
  default     = ""
}

variable "recovery_window_in_days" {
  description = "The number of days to recover a deleted secret (0 to delete immediately)"
  type        = number
  default     = 30
}

variable "allowed_principal_arns" {
  description = "List of IAM principal ARNs allowed to read this secret"
  type        = list(string)
  default     = []
}
