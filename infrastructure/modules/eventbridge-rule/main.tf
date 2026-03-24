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

  full_rule_name = "smartfreight-${var.environment}-${var.rule_name}"
  use_schedule   = var.schedule_expression != ""
  use_dlq        = var.dlq_arn != ""
}

# IAM Role for EventBridge to invoke targets
resource "aws_iam_role" "eventbridge" {
  name = "${local.full_rule_name}-eb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.full_rule_name}-eb-role"
  })
}

# IAM Policy based on target type
resource "aws_iam_role_policy" "target_invoke" {
  name = "${local.full_rule_name}-target-policy"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      var.target_type == "lambda" ? [
        {
          Effect   = "Allow"
          Action   = "lambda:InvokeFunction"
          Resource = var.target_arn
        }
      ] : [],
      var.target_type == "sqs" ? [
        {
          Effect   = "Allow"
          Action   = "sqs:SendMessage"
          Resource = var.target_arn
        }
      ] : [],
      var.target_type == "ecs" ? [
        {
          Effect = "Allow"
          Action = [
            "ecs:RunTask",
            "iam:PassRole"
          ]
          Resource = [
            var.ecs_task_definition_arn,
            var.target_arn
          ]
        }
      ] : [],
      local.use_dlq ? [
        {
          Effect   = "Allow"
          Action   = "sqs:SendMessage"
          Resource = var.dlq_arn
        }
      ] : []
    )
  })
}

# EventBridge Rule
resource "aws_cloudwatch_event_rule" "this" {
  name           = local.full_rule_name
  description    = var.description != "" ? var.description : "SmartFreight ${var.environment} rule: ${var.rule_name}"
  event_bus_name = var.event_bus_name

  schedule_expression = local.use_schedule ? var.schedule_expression : null
  event_pattern       = !local.use_schedule ? (var.event_pattern != "" ? var.event_pattern : null) : null

  is_enabled = var.is_enabled

  tags = merge(local.common_tags, {
    Name = local.full_rule_name
  })
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "this" {
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = var.event_bus_name
  arn            = var.target_arn
  role_arn       = aws_iam_role.eventbridge.arn
  target_id      = "${local.full_rule_name}-target"

  input = var.target_input != "" ? var.target_input : null

  dynamic "input_transformer" {
    for_each = var.target_input_transformer != null ? [var.target_input_transformer] : []
    content {
      input_paths    = input_transformer.value.input_paths
      input_template = input_transformer.value.input_template
    }
  }

  dynamic "ecs_target" {
    for_each = var.target_type == "ecs" ? [1] : []
    content {
      task_definition_arn = var.ecs_task_definition_arn
      task_count          = 1
      launch_type         = var.ecs_launch_type

      network_configuration {
        subnets          = var.ecs_subnet_ids
        security_groups  = var.ecs_security_group_ids
        assign_public_ip = var.ecs_assign_public_ip
      }
    }
  }

  retry_policy {
    maximum_retry_attempts       = var.retry_policy_max_attempts
    maximum_event_age_in_seconds = 3600
  }

  dynamic "dead_letter_config" {
    for_each = local.use_dlq ? [1] : []
    content {
      arn = var.dlq_arn
    }
  }
}

# Lambda permission (if target is Lambda)
resource "aws_lambda_permission" "eventbridge" {
  count         = var.target_type == "lambda" ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke-${local.full_rule_name}"
  action        = "lambda:InvokeFunction"
  function_name = var.target_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this.arn
}
