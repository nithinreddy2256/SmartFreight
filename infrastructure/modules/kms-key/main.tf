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

  full_alias = "alias/smartfreight/${var.environment}/${var.alias_name}"
}

# KMS Key Policy
data "aws_iam_policy_document" "key_policy" {
  # Allow root account full access
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow key administrators
  dynamic "statement" {
    for_each = length(var.additional_key_admins) > 0 ? [1] : []
    content {
      sid    = "AllowKeyAdministration"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.additional_key_admins
      }
      actions = [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion"
      ]
      resources = ["*"]
    }
  }

  # Allow key users (encrypt/decrypt)
  dynamic "statement" {
    for_each = length(var.additional_key_users) > 0 ? [1] : []
    content {
      sid    = "AllowKeyUsage"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.additional_key_users
      }
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
    }
  }

  # Allow AWS services to use the key
  statement {
    sid    = "AllowAWSServices"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "logs.${data.aws_region.current.name}.amazonaws.com",
        "secretsmanager.amazonaws.com",
        "s3.amazonaws.com",
        "sqs.amazonaws.com",
        "sns.amazonaws.com",
        "rds.amazonaws.com",
        "dynamodb.amazonaws.com"
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# KMS Key
resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  multi_region            = var.multi_region
  policy                  = data.aws_iam_policy_document.key_policy.json

  tags = merge(local.common_tags, {
    Name  = local.full_alias
    Alias = var.alias_name
  })
}

# KMS Key Alias
resource "aws_kms_alias" "this" {
  name          = local.full_alias
  target_key_id = aws_kms_key.this.key_id
}

# CloudWatch alarm for KMS key scheduled deletion
resource "aws_cloudwatch_metric_alarm" "key_deletion" {
  alarm_name          = "smartfreight-${var.environment}-kms-${var.alias_name}-deletion"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfRequestsForKeyStateChange"
  namespace           = "AWS/KMS"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when KMS key ${local.full_alias} has a pending deletion request"
  treat_missing_data  = "notBreaching"

  dimensions = {
    KeyId = aws_kms_key.this.key_id
  }

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-kms-${var.alias_name}-deletion-alarm"
  })
}
