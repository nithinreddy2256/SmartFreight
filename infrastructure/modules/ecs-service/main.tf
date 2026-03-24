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

  use_alb       = var.alb_target_group_arn != ""
  use_sqs_scale = var.sqs_queue_arn != ""
}

# CloudWatch Log Group for the service
resource "aws_cloudwatch_log_group" "service" {
  name              = "/ecs/smartfreight-${var.environment}/${var.service_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "/ecs/smartfreight-${var.environment}/${var.service_name}"
  })
}

# IAM: ECS Task Execution Role
resource "aws_iam_role" "task_execution" {
  name = "smartfreight-${var.environment}-${var.service_name}-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-${var.service_name}-exec-role"
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow execution role to read secrets
resource "aws_iam_role_policy" "task_execution_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0
  name  = "smartfreight-${var.environment}-${var.service_name}-exec-secrets"
  role  = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ]
        Resource = values(var.secrets)
      }
    ]
  })
}

# IAM: ECS Task Role (for the application itself)
resource "aws_iam_role" "task" {
  name = "smartfreight-${var.environment}-${var.service_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-${var.service_name}-task-role"
  })
}

# Allow X-Ray tracing
resource "aws_iam_role_policy_attachment" "task_xray" {
  role       = aws_iam_role.task.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "task_additional" {
  count      = length(var.task_role_policy_arns)
  role       = aws_iam_role.task.name
  policy_arn = var.task_role_policy_arns[count.index]
}

# ECS Task Definition
resource "aws_ecs_task_definition" "this" {
  family                   = "smartfreight-${var.environment}-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = var.service_name
      image = var.image_uri

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for k, v in var.environment_vars : {
          name  = k
          value = v
        }
      ]

      secrets = [
        for k, v in var.secrets : {
          name      = k
          valueFrom = v
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-${var.service_name}"
  })
}

# Security Group for the ECS service tasks
resource "aws_security_group" "service" {
  name        = "smartfreight-${var.environment}-${var.service_name}-sg"
  description = "Security group for ${var.service_name} ECS service"
  vpc_id      = data.aws_subnet.first.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.security_group_id]
    description     = "Allow traffic from ALB/caller security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-${var.service_name}-sg"
  })
}

data "aws_subnet" "first" {
  id = var.subnet_ids[0]
}

# ECS Service
resource "aws_ecs_service" "this" {
  name            = "smartfreight-${var.environment}-${var.service_name}"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.use_alb ? [1] : []
    content {
      target_group_arn = var.alb_target_group_arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = merge(local.common_tags, {
    Name = "smartfreight-${var.environment}-${var.service_name}"
  })
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${split("/", var.cluster_arn)[1]}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-Based Auto Scaling Policy
resource "aws_appautoscaling_policy" "cpu" {
  name               = "smartfreight-${var.environment}-${var.service_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_scale_up_threshold
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# SQS Queue-Based Auto Scaling Policy
resource "aws_appautoscaling_policy" "sqs" {
  count = local.use_sqs_scale ? 1 : 0

  name               = "smartfreight-${var.environment}-${var.service_name}-sqs-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      metrics {
        label = "Get the queue size (the number of messages waiting to be processed)"
        id    = "m1"
        metric_stat {
          metric {
            metric_name = "ApproximateNumberOfMessagesVisible"
            namespace   = "AWS/SQS"
            dimensions {
              name  = "QueueName"
              value = var.sqs_queue_name
            }
          }
          stat = "Sum"
        }
        return_data = false
      }
      metrics {
        label = "Get the ECS running task count (the number of currently running tasks)"
        id    = "m2"
        metric_stat {
          metric {
            metric_name = "RunningTaskCount"
            namespace   = "ECS/ContainerInsights"
            dimensions {
              name  = "ClusterName"
              value = split("/", var.cluster_arn)[1]
            }
            dimensions {
              name  = "ServiceName"
              value = aws_ecs_service.this.name
            }
          }
          stat = "Average"
        }
        return_data = false
      }
      metrics {
        label       = "Calculate the backlog per instance"
        id          = "e1"
        expression  = "m1 / m2"
        return_data = true
      }
    }
    target_value       = var.sqs_scale_up_threshold
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
