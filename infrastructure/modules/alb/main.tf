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

  full_alb_name    = "sf-${var.environment}-${var.alb_name}"
  use_https        = var.certificate_arn != ""
  use_access_logs  = var.access_logs_bucket != ""
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${local.full_alb_name}-sg"
  description = "Security group for ${local.full_alb_name} ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.internal ? [] : var.allowed_cidr_blocks
    self        = var.internal ? true : false
    description = "HTTP"
  }

  dynamic "ingress" {
    for_each = local.use_https ? [1] : []
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.internal ? [] : var.allowed_cidr_blocks
      self        = var.internal ? true : false
      description = "HTTPS"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${local.full_alb_name}-sg"
  })
}

# Application Load Balancer
resource "aws_lb" "this" {
  name               = local.full_alb_name
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.deletion_protection

  dynamic "access_logs" {
    for_each = local.use_access_logs ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = "${var.access_logs_prefix}/${local.full_alb_name}"
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = local.full_alb_name
  })
}

# HTTP Listener (always created - redirects to HTTPS if cert is provided, else forwards)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.use_https ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.use_https ? [] : [1]
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Service Unavailable"
        status_code  = "503"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.full_alb_name}-http-listener"
  })
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  count             = local.use_https ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Service Unavailable"
      status_code  = "503"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.full_alb_name}-https-listener"
  })
}

# Target Groups
resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name        = "sf-${var.environment}-${each.key}"
  port        = each.value.port
  protocol    = each.value.protocol
  vpc_id      = var.vpc_id
  target_type = each.value.target_type

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = each.value.health_check_path
    port                = lookup(each.value, "health_check_port", "traffic-port")
    protocol            = each.value.protocol
    matcher             = "200-299"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    Name = "sf-${var.environment}-${each.key}"
  })

  lifecycle {
    create_before_destroy = true
  }
}
