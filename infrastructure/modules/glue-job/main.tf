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

  full_job_name     = "smartfreight-${var.environment}-${var.job_name}"
  use_kms           = var.kms_key_arn != ""
  use_connection    = var.aurora_connection_string != "" && var.subnet_id != ""
  use_temp_bucket   = var.s3_temp_bucket != ""
}

# IAM Role for Glue
resource "aws_iam_role" "glue" {
  name = "${local.full_job_name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.full_job_name}-glue-role"
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  name = "${local.full_job_name}-s3-policy"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = ["arn:aws:s3:::smartfreight-*", "arn:aws:s3:::smartfreight-*/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "glue_kms" {
  count = local.use_kms ? 1 : 0
  name  = "${local.full_job_name}-kms-policy"
  role  = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [var.kms_key_arn]
      }
    ]
  })
}

# Glue Security Configuration
resource "aws_glue_security_configuration" "this" {
  count = local.use_kms ? 1 : 0
  name  = "${local.full_job_name}-security-config"

  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn                = var.kms_key_arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn                   = var.kms_key_arn
    }

    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn        = var.kms_key_arn
    }
  }
}

# Glue Connection for Aurora JDBC
resource "aws_glue_connection" "aurora" {
  count = local.use_connection ? 1 : 0

  name            = "${local.full_job_name}-aurora-connection"
  connection_type = "JDBC"

  connection_properties = {
    JDBC_CONNECTION_URL = var.aurora_connection_string
    USERNAME            = "placeholder"
    PASSWORD            = "placeholder"
  }

  physical_connection_requirements {
    availability_zone      = var.availability_zone
    security_group_id_list = [var.security_group_id]
    subnet_id              = var.subnet_id
  }

  tags = merge(local.common_tags, {
    Name = "${local.full_job_name}-aurora-connection"
  })
}

# Glue Job
resource "aws_glue_job" "this" {
  name              = local.full_job_name
  role_arn          = aws_iam_role.glue.arn
  glue_version      = var.glue_version
  max_retries       = var.max_retries
  timeout           = var.timeout
  connections       = local.use_connection ? [aws_glue_connection.aurora[0].name] : []
  security_configuration = local.use_kms ? aws_glue_security_configuration.this[0].name : null

  worker_type       = var.use_worker_type ? var.worker_type : null
  number_of_workers = var.use_worker_type ? var.number_of_workers : null
  max_capacity      = var.use_worker_type ? null : var.max_capacity

  command {
    name            = "glueetl"
    script_location = var.script_s3_location
    python_version  = var.python_version
  }

  default_arguments = merge(
    {
      "--job-language"                     = "python"
      "--enable-continuous-cloudwatch-log" = "true"
      "--enable-metrics"                   = "true"
      "--enable-job-insights"              = "true"
      "--job-bookmark-option"              = "job-bookmark-enable"
      "--TempDir"                          = local.use_temp_bucket ? "s3://${var.s3_temp_bucket}/glue-temp/${var.job_name}/" : ""
      "--enable-glue-datacatalog"          = "true"
    },
    var.default_arguments
  )

  tags = merge(local.common_tags, {
    Name = local.full_job_name
  })
}

# CloudWatch Log Group for Glue
resource "aws_cloudwatch_log_group" "glue" {
  name              = "/aws-glue/jobs/${local.full_job_name}"
  retention_in_days = 30
  kms_key_id        = local.use_kms ? var.kms_key_arn : null

  tags = merge(local.common_tags, {
    Name = "/aws-glue/jobs/${local.full_job_name}"
  })
}
