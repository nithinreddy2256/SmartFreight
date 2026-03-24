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

  use_kms           = var.kms_key_arn != ""
  use_sns           = var.sns_topic_arn != ""
  fifo_suffix       = var.fifo_queue ? ".fifo" : ""
  queue_name_full   = "${var.queue_name}-${var.environment}${local.fifo_suffix}"
  dlq_name_full     = "${var.queue_name}-${var.environment}-dlq${local.fifo_suffix}"
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name                              = local.dlq_name_full
  message_retention_seconds         = var.dlq_message_retention_seconds
  fifo_queue                        = var.fifo_queue
  content_based_deduplication       = var.fifo_queue ? var.content_based_deduplication : null
  kms_master_key_id                 = local.use_kms ? var.kms_key_arn : null
  kms_data_key_reuse_period_seconds = local.use_kms ? 300 : null

  tags = merge(local.common_tags, {
    Name = local.dlq_name_full
    Type = "dead-letter-queue"
  })
}

# Main Queue
resource "aws_sqs_queue" "this" {
  name                              = local.queue_name_full
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  message_retention_seconds         = var.message_retention_seconds
  delay_seconds                     = var.delay_seconds
  max_message_size                  = var.max_message_size
  receive_wait_time_seconds         = var.receive_wait_time_seconds
  fifo_queue                        = var.fifo_queue
  content_based_deduplication       = var.fifo_queue ? var.content_based_deduplication : null
  kms_master_key_id                 = local.use_kms ? var.kms_key_arn : null
  kms_data_key_reuse_period_seconds = local.use_kms ? 300 : null

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(local.common_tags, {
    Name = local.queue_name_full
    Type = "main-queue"
  })
}

# Queue policy to allow SNS topic to publish
resource "aws_sqs_queue_policy" "this" {
  count     = local.use_sns ? 1 : 0
  queue_url = aws_sqs_queue.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSNSPublish"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.this.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = var.sns_topic_arn
          }
        }
      }
    ]
  })
}

# SNS Subscription
resource "aws_sns_topic_subscription" "this" {
  count = local.use_sns ? 1 : 0

  topic_arn            = var.sns_topic_arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.this.arn
  filter_policy        = var.filter_policy != "" ? var.filter_policy : null
  raw_message_delivery = false

  depends_on = [aws_sqs_queue_policy.this]
}

# CloudWatch alarm for DLQ depth
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${local.dlq_name_full}-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages are present in the ${local.dlq_name_full} dead letter queue"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.dlq_name_full}-depth-alarm"
  })
}
