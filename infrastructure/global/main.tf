terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "smartfreight-terraform-state-global"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "smartfreight-terraform-locks-global"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "smartfreight"
      Scope     = "global"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ============================================================
# ECR Repositories (shared across all environments)
# One repo per microservice - environments use image tags
# ============================================================

locals {
  services = [
    "shipment-orchestrator",
    "carrier-integration",
    "invoice-processing",
    "notification",
    "document-management",
    "analytics",
  ]

  lambda_functions = [
    "invoice-ocr-trigger",
    "carrier-rate-refresh",
    "s3-document-processor",
    "carrier-webhook-handler",
  ]
}

module "ecr" {
  for_each = toset(local.services)
  source   = "../modules/ecr-repository"

  repository_name      = "smartfreight/${each.key}"
  environment          = "global"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  keep_image_count     = 10

  # Allow all environment accounts to pull
  allowed_account_ids = var.allowed_account_ids
}

module "ecr_lambda" {
  for_each = toset(local.lambda_functions)
  source   = "../modules/ecr-repository"

  repository_name      = "smartfreight/lambda/${each.key}"
  environment          = "global"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  keep_image_count     = 10

  allowed_account_ids = var.allowed_account_ids
}

# ============================================================
# Route53 Hosted Zones
# ============================================================

# Public hosted zone (for external DNS)
resource "aws_route53_zone" "public" {
  name    = var.public_domain
  comment = "SmartFreight public hosted zone - managed by Terraform"

  tags = {
    Name      = var.public_domain
    ManagedBy = "terraform"
    Scope     = "global"
  }
}

# Private hosted zone for internal service discovery (shared across VPCs)
resource "aws_route53_zone" "private" {
  name    = var.private_domain
  comment = "SmartFreight private hosted zone for internal service discovery"

  dynamic "vpc" {
    for_each = var.vpc_ids
    content {
      vpc_id = vpc.value
    }
  }

  tags = {
    Name      = var.private_domain
    ManagedBy = "terraform"
    Scope     = "global"
  }
}

# ============================================================
# Route53 Records for each environment ALB
# ============================================================

resource "aws_route53_record" "dev_api" {
  count   = var.dev_alb_dns_name != "" ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "api.dev.${var.private_domain}"
  type    = "CNAME"
  ttl     = 60
  records = [var.dev_alb_dns_name]
}

resource "aws_route53_record" "test_api" {
  count   = var.test_alb_dns_name != "" ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "api.test.${var.private_domain}"
  type    = "CNAME"
  ttl     = 60
  records = [var.test_alb_dns_name]
}

resource "aws_route53_record" "prod_api" {
  count   = var.prod_alb_dns_name != "" ? 1 : 0
  zone_id = aws_route53_zone.public.zone_id
  name    = "api.${var.public_domain}"
  type    = "CNAME"
  ttl     = 60
  records = [var.prod_alb_dns_name]
}

# ============================================================
# IAM: Cross-Account roles for CI/CD ECR access
# ============================================================

resource "aws_iam_role" "cicd_ecr_push" {
  name = "smartfreight-cicd-ecr-push-role"
  description = "Role for CI/CD pipelines to push images to ECR"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            for account_id in var.allowed_account_ids :
            "arn:aws:iam::${account_id}:root"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "smartfreight-cicd-ecr-push-role"
    ManagedBy = "terraform"
    Scope     = "global"
  }
}

resource "aws_iam_role_policy" "cicd_ecr_push" {
  name = "smartfreight-cicd-ecr-push-policy"
  role = aws_iam_role.cicd_ecr_push.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
        Resource = concat(
          [
            for svc in local.services :
            "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/smartfreight/${svc}"
          ],
          [
            for fn in local.lambda_functions :
            "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/smartfreight/lambda/${fn}"
          ]
        )
      }
    ]
  })
}
