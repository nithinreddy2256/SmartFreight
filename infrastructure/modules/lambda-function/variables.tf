variable "function_name" {
  description = "The name of the Lambda function"
  type        = string
}

variable "environment" {
  description = "The deployment environment (dev, test, prod)"
  type        = string
}

variable "handler" {
  description = "The function entrypoint (e.g., index.handler)"
  type        = string
}

variable "runtime" {
  description = "The runtime identifier (e.g., python3.11, nodejs20.x)"
  type        = string
}

variable "filename" {
  description = "The path to the function's deployment package (zip file)"
  type        = string
  default     = ""
}

variable "s3_bucket" {
  description = "S3 bucket where the deployment package is stored"
  type        = string
  default     = ""
}

variable "s3_key" {
  description = "S3 object key of the deployment package"
  type        = string
  default     = ""
}

variable "image_uri" {
  description = "ECR image URI for container image deployment (overrides filename/s3 when set)"
  type        = string
  default     = ""
}

variable "memory_size" {
  description = "Amount of memory in MB your Lambda function can use at runtime"
  type        = number
  default     = 256
}

variable "timeout" {
  description = "The amount of time your Lambda function has to run in seconds"
  type        = number
  default     = 30
}

variable "environment_vars" {
  description = "Map of environment variable names to values"
  type        = map(string)
  default     = {}
}

variable "vpc_config" {
  description = "VPC configuration for the Lambda function (optional)"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key to encrypt the Lambda function's environment variables"
  type        = string
  default     = ""
}

variable "reserved_concurrent_executions" {
  description = "The amount of reserved concurrent executions for this Lambda (-1 for unreserved)"
  type        = number
  default     = -1
}

variable "architectures" {
  description = "Instruction set architecture for your Lambda function (x86_64 or arm64)"
  type        = list(string)
  default     = ["x86_64"]
}

variable "layers" {
  description = "List of Lambda layer ARNs to attach to the function"
  type        = list(string)
  default     = []
}

variable "sqs_event_source_arns" {
  description = "List of SQS queue ARNs to use as event sources"
  type        = list(string)
  default     = []
}

variable "sqs_batch_size" {
  description = "The largest number of SQS records that Lambda will retrieve from the queue at the time of invocation"
  type        = number
  default     = 10
}

variable "additional_policy_arns" {
  description = "List of additional IAM policy ARNs to attach to the Lambda execution role"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "The number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}
