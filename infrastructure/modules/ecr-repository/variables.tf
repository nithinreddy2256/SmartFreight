variable "repository_name" {
  description = "The name of the ECR repository"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for the repository (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "IMMUTABLE"
}

variable "scan_on_push" {
  description = "Whether images are scanned after being pushed to the repository"
  type        = bool
  default     = true
}

variable "keep_image_count" {
  description = "Number of images to keep per tag (lifecycle policy)"
  type        = number
  default     = 10
}

variable "allowed_account_ids" {
  description = "List of AWS account IDs allowed to pull images from this repository"
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key for server-side encryption (optional, uses AES256 if not provided)"
  type        = string
  default     = ""
}
