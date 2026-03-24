terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  full_secret_name = "smartfreight/${var.environment}/${var.secret_name}"
  use_kms          = var.kms_key_arn != ""
  use_rotation     = var.rotation_lambda_arn != ""
  has_initial_value = var.secret_string != ""
}

# Secrets Manager Secret
resource "aws_secretsmanager_secret" "this" {
  name                    = local.full_secret_name
  description             = var.description != "" ? var.description : "SmartFreight ${var.environment} secret: ${var.secret_name}"
  kms_key_id              = local.use_kms ? var.kms_key_arn : null
  recovery_window_in_days = var.environment == "prod" ? var.recovery_window_in_days : 0

  tags = merge(local.common_tags, {
    Name = local.full_secret_name
  })
}

# Initial secret value
resource "aws_secretsmanager_secret_version" "this" {
  count         = local.has_initial_value ? 1 : 0
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.secret_string

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Resource policy
resource "aws_secretsmanager_secret_policy" "this" {
  count      = length(var.allowed_principal_arns) > 0 ? 1 : 0
  secret_arn = aws_secretsmanager_secret.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSpecificPrincipals"
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_principal_arns
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.this.arn
      }
    ]
  })
}

# Lambda permission for rotation
resource "aws_lambda_permission" "rotation" {
  count         = local.use_rotation ? 1 : 0
  statement_id  = "AllowSecretsManagerRotation-${replace(local.full_secret_name, "/", "-")}"
  action        = "lambda:InvokeFunction"
  function_name = var.rotation_lambda_arn
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.this.arn
}

# Rotation configuration
resource "aws_secretsmanager_secret_rotation" "this" {
  count               = local.use_rotation ? 1 : 0
  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [aws_lambda_permission.rotation]
}
