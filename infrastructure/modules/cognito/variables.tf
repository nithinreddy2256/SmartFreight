variable "user_pool_name" {
  description = "The name of the Cognito User Pool"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "callback_urls" {
  description = "List of allowed callback URLs for the app client"
  type        = list(string)
  default     = []
}

variable "logout_urls" {
  description = "List of allowed sign-out URLs for the app client"
  type        = list(string)
  default     = []
}

variable "domain_prefix" {
  description = "The domain prefix for the Cognito hosted UI"
  type        = string
}

variable "resource_server_identifier" {
  description = "The identifier for the M2M resource server (e.g., https://api.smartfreight.com)"
  type        = string
  default     = "https://api.smartfreight.com"
}

variable "resource_server_scopes" {
  description = "List of custom scopes for the M2M resource server"
  type = list(object({
    scope_name        = string
    scope_description = string
  }))
  default = [
    {
      scope_name        = "read"
      scope_description = "Read access"
    },
    {
      scope_name        = "write"
      scope_description = "Write access"
    }
  ]
}

variable "password_minimum_length" {
  description = "Minimum length for user passwords"
  type        = number
  default     = 12
}

variable "mfa_configuration" {
  description = "MFA configuration (OFF, ON, OPTIONAL)"
  type        = string
  default     = "OPTIONAL"
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key for custom encryption (optional)"
  type        = string
  default     = ""
}
