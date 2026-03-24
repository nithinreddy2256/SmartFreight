terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  full_function_name = "smartfreight-${var.environment}-${var.function_name}"
  use_kms            = var.kms_key_arn != ""
  use_vpc            = var.vpc_config != null
  use_image          = var.image_uri != ""
  use_s3_package     = !local.use_image && var.s3_bucket != "" && var.s3_key != ""
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.full_function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.use_kms ? var.kms_key_arn : null

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.full_function_name}"
  })
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda" {
  name = "${local.full_function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.full_function_name}-role"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = local.use_vpc ? "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" : "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach X-Ray write policy
resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Allow Lambda to read from SQS (if event sources are specified)
resource "aws_iam_role_policy" "sqs_access" {
  count = length(var.sqs_event_source_arns) > 0 ? 1 : 0
  name  = "${local.full_function_name}-sqs-policy"
  role  = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_event_source_arns
      }
    ]
  })
}

# Attach additional policies
resource "aws_iam_role_policy_attachment" "additional" {
  count      = length(var.additional_policy_arns)
  role       = aws_iam_role.lambda.name
  policy_arn = var.additional_policy_arns[count.index]
}

# Lambda Function
resource "aws_lambda_function" "this" {
  function_name = local.full_function_name
  role          = aws_iam_role.lambda.arn
  memory_size   = var.memory_size
  timeout       = var.timeout
  architectures = var.architectures

  # Container image deployment (handler/runtime/layers not used with image_uri)
  package_type = local.use_image ? "Image" : "Zip"
  image_uri    = local.use_image ? var.image_uri : null

  # Zip deployment
  handler          = local.use_image ? null : var.handler
  runtime          = local.use_image ? null : var.runtime
  layers           = local.use_image ? [] : var.layers
  filename         = local.use_image ? null : (local.use_s3_package ? null : (var.filename != "" ? var.filename : null))
  s3_bucket        = local.use_image ? null : (local.use_s3_package ? var.s3_bucket : null)
  s3_key           = local.use_image ? null : (local.use_s3_package ? var.s3_key : null)
  source_code_hash = local.use_image ? null : (local.use_s3_package ? null : (var.filename != "" ? filebase64sha256(var.filename) : null))

  reserved_concurrent_executions = var.reserved_concurrent_executions

  kms_key_arn = local.use_kms ? var.kms_key_arn : null

  environment {
    variables = merge(
      var.environment_vars,
      {
        ENVIRONMENT = var.environment
        AWS_REGION  = data.aws_region.current.name
      }
    )
  }

  dynamic "vpc_config" {
    for_each = local.use_vpc ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
    aws_cloudwatch_log_group.this
  ]

  tags = merge(local.common_tags, {
    Name = local.full_function_name
  })
}

# SQS Event Source Mappings
resource "aws_lambda_event_source_mapping" "sqs" {
  count = length(var.sqs_event_source_arns)

  event_source_arn = var.sqs_event_source_arns[count.index]
  function_name    = aws_lambda_function.this.arn
  batch_size       = var.sqs_batch_size
  enabled          = true

  function_response_types = ["ReportBatchItemFailures"]
}
