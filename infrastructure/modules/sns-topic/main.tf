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

  use_kms     = var.kms_key_arn != ""
  fifo_suffix = var.fifo_topic ? ".fifo" : ""
  topic_name  = "${var.topic_name}-${var.environment}${local.fifo_suffix}"
  dlq_name    = "${var.topic_name}-${var.environment}-dlq"
}

# SNS Topic
resource "aws_sns_topic" "this" {
  name                        = local.topic_name
  display_name                = var.display_name != "" ? var.display_name : var.topic_name
  kms_master_key_id           = local.use_kms ? var.kms_key_arn : null
  fifo_topic                  = var.fifo_topic
  content_based_deduplication = var.fifo_topic ? var.content_based_deduplication : null

  tags = merge(local.common_tags, {
    Name = local.topic_name
  })
}

# Dead Letter Queue for the SNS topic (for failed deliveries)
resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = local.use_kms ? var.kms_key_arn : null

  tags = merge(local.common_tags, {
    Name = local.dlq_name
    Type = "sns-dead-letter-queue"
  })
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "this" {
  arn = aws_sns_topic.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "AllowAccountPublish"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          }
          Action   = "sns:Publish"
          Resource = aws_sns_topic.this.arn
        }
      ],
      length(var.allowed_publish_principals) > 0 ? [
        {
          Sid    = "AllowSpecificPrincipals"
          Effect = "Allow"
          Principal = {
            AWS = var.allowed_publish_principals
          }
          Action   = "sns:Publish"
          Resource = aws_sns_topic.this.arn
        }
      ] : []
    )
  })
}

# CloudWatch alarm for DLQ depth
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${local.dlq_name}-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages are present in the SNS dead letter queue ${local.dlq_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.dlq_name}-depth-alarm"
  })
}
