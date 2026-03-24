terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  dashboard_name     = "smartfreight-${var.environment}-${var.service_name}"
  use_alarm_sns      = var.alarm_sns_topic_arn != ""
  monitor_ecs        = var.ecs_cluster_name != "" && length(var.ecs_service_names) > 0
  monitor_alb        = var.alb_arn_suffix != ""
  monitor_rds        = var.rds_cluster_identifier != ""
}

# Log Metric Filters
resource "aws_cloudwatch_log_metric_filter" "custom" {
  count = length(var.log_metric_filters)

  name           = "${var.service_name}-${var.environment}-${var.log_metric_filters[count.index].name}"
  log_group_name = var.log_metric_filters[count.index].log_group_name
  pattern        = var.log_metric_filters[count.index].filter_pattern

  metric_transformation {
    name      = var.log_metric_filters[count.index].metric_name
    namespace = var.log_metric_filters[count.index].metric_namespace
    value     = var.log_metric_filters[count.index].metric_value
  }
}

# Default error rate metric filter
resource "aws_cloudwatch_log_metric_filter" "error_rate" {
  count = length(var.log_group_names) > 0 ? 1 : 0

  name           = "${var.service_name}-${var.environment}-error-count"
  log_group_name = var.log_group_names[0]
  pattern        = "[timestamp, requestId, level=ERROR*, ...]"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "SmartFreight/${var.environment}/${var.service_name}"
    value     = "1"
    unit      = "Count"
  }
}

# ECS CPU Alarm (per service)
resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  count = local.monitor_ecs ? length(var.ecs_service_names) : 0

  alarm_name          = "smartfreight-${var.environment}-${var.ecs_service_names[count.index]}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_threshold_percent
  alarm_description   = "ECS service ${var.ecs_service_names[count.index]} CPU utilization is high"
  treat_missing_data  = "missing"
  alarm_actions       = local.use_alarm_sns ? [var.alarm_sns_topic_arn] : []
  ok_actions          = local.use_alarm_sns ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_names[count.index]
  }

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-${var.ecs_service_names[count.index]}-cpu-high"
  })
}

# ECS Memory Alarm (per service)
resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  count = local.monitor_ecs ? length(var.ecs_service_names) : 0

  alarm_name          = "smartfreight-${var.environment}-${var.ecs_service_names[count.index]}-memory-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.memory_threshold_percent
  alarm_description   = "ECS service ${var.ecs_service_names[count.index]} memory utilization is high"
  treat_missing_data  = "missing"
  alarm_actions       = local.use_alarm_sns ? [var.alarm_sns_topic_arn] : []
  ok_actions          = local.use_alarm_sns ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_names[count.index]
  }

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-${var.ecs_service_names[count.index]}-memory-high"
  })
}

# ALB Latency Alarm
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  count = local.monitor_alb ? 1 : 0

  alarm_name          = "smartfreight-${var.environment}-alb-latency-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "p99"
  threshold           = var.latency_threshold_ms / 1000.0
  alarm_description   = "ALB p99 response time is above ${var.latency_threshold_ms}ms"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.use_alarm_sns ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-alb-latency-high"
  })
}

# ALB 5xx Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = local.monitor_alb ? 1 : 0

  alarm_name          = "smartfreight-${var.environment}-alb-5xx-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.error_threshold
  alarm_description   = "ALB is experiencing a high rate of 5xx errors"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.use_alarm_sns ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-alb-5xx-errors"
  })
}

# RDS CPU Alarm
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count = local.monitor_rds ? 1 : 0

  alarm_name          = "smartfreight-${var.environment}-rds-${var.rds_cluster_identifier}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS cluster ${var.rds_cluster_identifier} CPU utilization is high"
  treat_missing_data  = "missing"
  alarm_actions       = local.use_alarm_sns ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    DBClusterIdentifier = var.rds_cluster_identifier
  }

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-rds-${var.rds_cluster_identifier}-cpu-high"
  })
}

# Composite Alarm for overall service health
resource "aws_cloudwatch_composite_alarm" "service_health" {
  count = local.monitor_ecs && local.monitor_alb ? 1 : 0

  alarm_name        = "smartfreight-${var.environment}-${var.service_name}-health"
  alarm_description = "Composite alarm for overall health of ${var.service_name} in ${var.environment}"

  alarm_rule = join(" OR ", concat(
    local.monitor_alb ? [
      "ALARM(${aws_cloudwatch_metric_alarm.alb_5xx[0].alarm_name})",
      "ALARM(${aws_cloudwatch_metric_alarm.alb_latency[0].alarm_name})"
    ] : [],
    [
      for alarm in aws_cloudwatch_metric_alarm.ecs_cpu : "ALARM(${alarm.alarm_name})"
    ]
  ))

  alarm_actions = local.use_alarm_sns ? [var.alarm_sns_topic_arn] : []
  ok_actions    = local.use_alarm_sns ? [var.alarm_sns_topic_arn] : []

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-${var.service_name}-health"
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = concat(
      local.monitor_ecs ? [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "ECS CPU Utilization"
            view   = "timeSeries"
            region = "us-east-1"
            metrics = [
              for svc in var.ecs_service_names : [
                "AWS/ECS",
                "CPUUtilization",
                "ClusterName", var.ecs_cluster_name,
                "ServiceName", svc
              ]
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "ECS Memory Utilization"
            view   = "timeSeries"
            region = "us-east-1"
            metrics = [
              for svc in var.ecs_service_names : [
                "AWS/ECS",
                "MemoryUtilization",
                "ClusterName", var.ecs_cluster_name,
                "ServiceName", svc
              ]
            ]
          }
        }
      ] : [],
      local.monitor_alb ? [
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 12
          height = 6
          properties = {
            title  = "ALB Response Time (p99)"
            view   = "timeSeries"
            region = "us-east-1"
            metrics = [
              ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { "stat" : "p99" }]
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 6
          width  = 12
          height = 6
          properties = {
            title  = "ALB HTTP Error Codes"
            view   = "timeSeries"
            region = "us-east-1"
            metrics = [
              ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix, { "stat" : "Sum" }],
              ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { "stat" : "Sum" }]
            ]
          }
        }
      ] : [],
      length(var.log_group_names) > 0 ? [
        {
          type   = "log"
          x      = 0
          y      = 12
          width  = 24
          height = 6
          properties = {
            title   = "Application Error Logs"
            view    = "table"
            query   = "SOURCE '${var.log_group_names[0]}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50"
            region  = "us-east-1"
          }
        }
      ] : []
    )
  })
}
