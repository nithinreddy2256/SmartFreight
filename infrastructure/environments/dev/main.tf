terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "smartfreight"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  env = var.environment

  # ECR base URL
  ecr_base_url        = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  lambda_image_tag    = "latest"

  # Service definitions
  microservices = {
    shipment-service = {
      port = 8080
    }
    carrier-service = {
      port = 8081
    }
    invoice-service = {
      port = 8082
    }
    document-service = {
      port = 8083
    }
    notification-service = {
      port = 8084
    }
    analytics-service = {
      port = 8085
    }
  }
}

# ============================================================
# KMS Key (single key for dev environment)
# ============================================================
module "kms" {
  source = "../../modules/kms-key"

  alias_name              = "main"
  description             = "SmartFreight dev environment master KMS key"
  environment             = local.env
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

# ============================================================
# VPC
# ============================================================
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr           = var.vpc_cidr
  environment        = local.env
  single_nat_gateway = true
}

# ============================================================
# ALB (Internal)
# ============================================================
module "alb" {
  source = "../../modules/alb"

  alb_name           = "internal"
  environment        = local.env
  internal           = true
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  certificate_arn    = var.certificate_arn
  access_logs_bucket = module.s3_alb_logs.bucket_name
  deletion_protection = false

  target_groups = {
    for name, cfg in local.microservices : name => {
      port              = cfg.port
      protocol          = "HTTP"
      target_type       = "ip"
      health_check_path = "/health"
    }
  }

  depends_on = [module.s3_alb_logs]
}

# ============================================================
# ECS Cluster
# ============================================================
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  cluster_name = "smartfreight-${local.env}"
  environment  = local.env
}

# ============================================================
# ECS Services (all 6 microservices)
# ============================================================
module "ecs_service" {
  for_each = local.microservices
  source   = "../../modules/ecs-service"

  service_name         = each.key
  environment          = local.env
  cluster_arn          = module.ecs_cluster.cluster_arn
  image_uri            = "${local.ecr_base_url}/smartfreight/${each.key}:latest"
  cpu                  = 256
  memory               = 512
  desired_count        = 1
  container_port       = each.value.port
  subnet_ids           = module.vpc.private_subnet_ids
  security_group_id    = module.alb.security_group_id
  alb_target_group_arn = module.alb.target_group_arns[each.key]
  min_capacity         = 1
  max_capacity         = 4

  environment_vars = {
    ENVIRONMENT      = local.env
    AWS_REGION       = var.aws_region
    LOG_LEVEL        = "DEBUG"
    SERVICE_NAME     = each.key
  }

  task_role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
  ]

  depends_on = [module.ecs_cluster, module.alb]
}

# ============================================================
# Aurora Clusters
# ============================================================
module "aurora_shipment_db" {
  source = "../../modules/aurora"

  cluster_identifier  = "smartfreight-${local.env}-shipment-db"
  database_name       = "shipment_db"
  environment         = local.env
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  serverless          = true
  min_acu             = 0.5
  max_acu             = 4.0
  deletion_protection = false
  kms_key_arn         = module.kms.key_arn

  allowed_security_group_ids = [
    for svc in ["shipment-service", "carrier-service"] :
    module.ecs_service[svc].security_group_id
  ]

  depends_on = [module.vpc, module.kms]
}

module "aurora_invoice_db" {
  source = "../../modules/aurora"

  cluster_identifier  = "smartfreight-${local.env}-invoice-db"
  database_name       = "invoice_db"
  environment         = local.env
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  serverless          = true
  min_acu             = 0.5
  max_acu             = 4.0
  deletion_protection = false
  kms_key_arn         = module.kms.key_arn

  allowed_security_group_ids = [
    module.ecs_service["invoice-service"].security_group_id
  ]

  depends_on = [module.vpc, module.kms]
}

# ============================================================
# DynamoDB Tables
# ============================================================
module "dynamodb_carrier_rate" {
  source = "../../modules/dynamodb-table"

  table_name   = "smartfreight-${local.env}-CarrierRateTable"
  environment  = local.env
  hash_key     = "CarrierId"
  range_key    = "RouteId"
  billing_mode = "PAY_PER_REQUEST"
  kms_key_arn  = module.kms.key_arn

  attributes = [
    { name = "CarrierId", type = "S" },
    { name = "RouteId", type = "S" },
    { name = "EffectiveDate", type = "S" }
  ]

  global_secondary_indexes = [
    {
      name            = "RouteId-EffectiveDate-index"
      hash_key        = "RouteId"
      range_key       = "EffectiveDate"
      projection_type = "ALL"
    }
  ]

  ttl_attribute  = "ExpiresAt"
  stream_enabled = true

  depends_on = [module.kms]
}

module "dynamodb_tracking_event" {
  source = "../../modules/dynamodb-table"

  table_name   = "smartfreight-${local.env}-TrackingEventTable"
  environment  = local.env
  hash_key     = "ShipmentId"
  range_key    = "EventTimestamp"
  billing_mode = "PAY_PER_REQUEST"
  kms_key_arn  = module.kms.key_arn

  attributes = [
    { name = "ShipmentId", type = "S" },
    { name = "EventTimestamp", type = "S" },
    { name = "Status", type = "S" }
  ]

  global_secondary_indexes = [
    {
      name            = "Status-EventTimestamp-index"
      hash_key        = "Status"
      range_key       = "EventTimestamp"
      projection_type = "ALL"
    }
  ]

  ttl_attribute  = "ExpiresAt"
  stream_enabled = true

  depends_on = [module.kms]
}

module "dynamodb_document_index" {
  source = "../../modules/dynamodb-table"

  table_name   = "smartfreight-${local.env}-DocumentIndexTable"
  environment  = local.env
  hash_key     = "DocumentId"
  range_key    = "EntityId"
  billing_mode = "PAY_PER_REQUEST"
  kms_key_arn  = module.kms.key_arn

  attributes = [
    { name = "DocumentId", type = "S" },
    { name = "EntityId", type = "S" },
    { name = "DocumentType", type = "S" }
  ]

  global_secondary_indexes = [
    {
      name            = "EntityId-DocumentType-index"
      hash_key        = "EntityId"
      range_key       = "DocumentType"
      projection_type = "ALL"
    }
  ]

  stream_enabled = false

  depends_on = [module.kms]
}

# ============================================================
# S3 Buckets
# ============================================================
module "s3_documents" {
  source = "../../modules/s3-bucket"

  bucket_name               = "smartfreight-${local.env}-documents-${data.aws_caller_identity.current.account_id}"
  environment               = local.env
  versioning_enabled        = true
  lifecycle_expiration_days = 365
  kms_key_arn               = module.kms.key_arn
  force_destroy             = true

  depends_on = [module.kms]
}

module "s3_etl_raw" {
  source = "../../modules/s3-bucket"

  bucket_name               = "smartfreight-${local.env}-etl-raw-${data.aws_caller_identity.current.account_id}"
  environment               = local.env
  versioning_enabled        = false
  lifecycle_expiration_days = 90
  kms_key_arn               = module.kms.key_arn
  force_destroy             = true

  depends_on = [module.kms]
}

module "s3_etl_processed" {
  source = "../../modules/s3-bucket"

  bucket_name               = "smartfreight-${local.env}-etl-processed-${data.aws_caller_identity.current.account_id}"
  environment               = local.env
  versioning_enabled        = false
  lifecycle_expiration_days = 90
  kms_key_arn               = module.kms.key_arn
  force_destroy             = true

  depends_on = [module.kms]
}

module "s3_reports" {
  source = "../../modules/s3-bucket"

  bucket_name               = "smartfreight-${local.env}-reports-${data.aws_caller_identity.current.account_id}"
  environment               = local.env
  versioning_enabled        = true
  lifecycle_expiration_days = 180
  kms_key_arn               = module.kms.key_arn
  force_destroy             = true

  depends_on = [module.kms]
}

module "s3_alb_logs" {
  source = "../../modules/s3-bucket"

  bucket_name               = "smartfreight-${local.env}-alb-logs-${data.aws_caller_identity.current.account_id}"
  environment               = local.env
  versioning_enabled        = false
  lifecycle_expiration_days = 30
  force_destroy             = true
}

# ============================================================
# SNS Topics
# ============================================================
module "sns_shipment_events" {
  source = "../../modules/sns-topic"

  topic_name  = "shipment-events"
  environment = local.env
  kms_key_arn = module.kms.key_arn

  depends_on = [module.kms]
}

module "sns_invoice_events" {
  source = "../../modules/sns-topic"

  topic_name  = "invoice-events"
  environment = local.env
  kms_key_arn = module.kms.key_arn

  depends_on = [module.kms]
}

module "sns_carrier_events" {
  source = "../../modules/sns-topic"

  topic_name  = "carrier-events"
  environment = local.env
  kms_key_arn = module.kms.key_arn

  depends_on = [module.kms]
}

module "sns_alerts" {
  source = "../../modules/sns-topic"

  topic_name  = "alerts"
  environment = local.env
  kms_key_arn = module.kms.key_arn

  depends_on = [module.kms]
}

# ============================================================
# SQS Queues
# ============================================================
module "sqs_notification" {
  source = "../../modules/sqs-queue"

  queue_name                = "notification"
  environment               = local.env
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  max_receive_count          = 3
  kms_key_arn                = module.kms.key_arn
  sns_topic_arn              = module.sns_shipment_events.topic_arn

  depends_on = [module.kms, module.sns_shipment_events]
}

module "sqs_invoice_processing" {
  source = "../../modules/sqs-queue"

  queue_name                = "invoice-processing"
  environment               = local.env
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600
  max_receive_count          = 3
  kms_key_arn                = module.kms.key_arn
  sns_topic_arn              = module.sns_invoice_events.topic_arn

  depends_on = [module.kms, module.sns_invoice_events]
}

module "sqs_analytics" {
  source = "../../modules/sqs-queue"

  queue_name                = "analytics"
  environment               = local.env
  visibility_timeout_seconds = 120
  message_retention_seconds  = 86400
  max_receive_count          = 5
  kms_key_arn                = module.kms.key_arn

  depends_on = [module.kms]
}

module "sqs_shipment_inbound" {
  source = "../../modules/sqs-queue"

  queue_name                = "shipment-inbound"
  environment               = local.env
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
  max_receive_count          = 3
  kms_key_arn                = module.kms.key_arn

  depends_on = [module.kms]
}

module "sqs_carrier_inbound" {
  source = "../../modules/sqs-queue"

  queue_name                = "carrier-inbound"
  environment               = local.env
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600
  max_receive_count          = 3
  kms_key_arn                = module.kms.key_arn
  sns_topic_arn              = module.sns_carrier_events.topic_arn

  depends_on = [module.kms, module.sns_carrier_events]
}

# ============================================================
# Cognito
# ============================================================
module "cognito" {
  source = "../../modules/cognito"

  user_pool_name = "users"
  environment    = local.env
  domain_prefix  = var.cognito_domain_prefix
  callback_urls  = var.cognito_callback_urls
  logout_urls    = ["https://dev.smartfreight.internal/logout"]

  resource_server_identifier = "https://api.smartfreight.dev"
  resource_server_scopes = [
    {
      scope_name        = "read"
      scope_description = "Read access to SmartFreight APIs"
    },
    {
      scope_name        = "write"
      scope_description = "Write access to SmartFreight APIs"
    }
  ]

  mfa_configuration = "OPTIONAL"
}

# ============================================================
# Lambda Functions (container image deployments)
# ============================================================
module "lambda_invoice_ocr_trigger" {
  source = "../../modules/lambda-function"

  function_name = "invoice-ocr-trigger"
  environment   = local.env
  image_uri     = "${local.ecr_base_url}/smartfreight/lambda/invoice-ocr-trigger:${local.lambda_image_tag}"
  memory_size   = 256
  timeout       = 60
  kms_key_arn   = module.kms.key_arn

  environment_vars = {
    INVOICE_PROCESSING_QUEUE_URL = module.sqs_invoice_processing.queue_url
  }

  additional_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonTextractFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
  ]

  depends_on = [module.kms, module.sqs_invoice_processing]
}

module "lambda_carrier_rate_refresh" {
  source = "../../modules/lambda-function"

  function_name = "carrier-rate-refresh"
  environment   = local.env
  image_uri     = "${local.ecr_base_url}/smartfreight/lambda/carrier-rate-refresh:${local.lambda_image_tag}"
  memory_size   = 256
  timeout       = 300
  kms_key_arn   = module.kms.key_arn

  environment_vars = {
    CARRIER_RATE_TABLE_NAME    = module.dynamodb_carrier_rate.table_name
    CARRIER_EVENTS_TOPIC_ARN   = module.sns_carrier_events.topic_arn
    CARRIER_IDS                = "fedex,ups,dhl"
    SECRETS_PREFIX             = "/smartfreight/${local.env}"
  }

  additional_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
  ]

  depends_on = [module.kms, module.dynamodb_carrier_rate, module.sns_carrier_events]
}

module "lambda_s3_document_processor" {
  source = "../../modules/lambda-function"

  function_name = "s3-document-processor"
  environment   = local.env
  image_uri     = "${local.ecr_base_url}/smartfreight/lambda/s3-document-processor:${local.lambda_image_tag}"
  memory_size   = 256
  timeout       = 30
  kms_key_arn   = module.kms.key_arn

  environment_vars = {
    DOCUMENT_INDEX_TABLE = module.dynamodb_document_index.table_name
  }

  additional_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
  ]

  depends_on = [module.kms, module.dynamodb_document_index]
}

module "lambda_carrier_webhook_handler" {
  source = "../../modules/lambda-function"

  function_name = "carrier-webhook-handler"
  environment   = local.env
  image_uri     = "${local.ecr_base_url}/smartfreight/lambda/carrier-webhook-handler:${local.lambda_image_tag}"
  memory_size   = 512
  timeout       = 30
  kms_key_arn   = module.kms.key_arn

  environment_vars = {
    SHIPMENT_EVENTS_TOPIC_ARN = module.sns_shipment_events.topic_arn
  }

  additional_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
  ]

  depends_on = [module.kms, module.sns_shipment_events]
}

# ============================================================
# Glue ETL Jobs
# ============================================================
module "glue_freight_spend_aggregator" {
  source = "../../modules/glue-job"

  job_name             = "freight-spend-aggregator"
  environment          = local.env
  script_s3_location   = "s3://${module.s3_etl_raw.bucket_name}/glue-scripts/freight_spend_aggregator.py"
  kms_key_arn          = module.kms.key_arn
  aurora_connection_string = "jdbc:postgresql://${module.aurora_invoice_db.cluster_endpoint}:5432/invoice_db"
  aurora_username      = var.aurora_glue_username
  aurora_password      = var.aurora_glue_password
  subnet_id            = module.vpc.private_subnet_ids[0]
  security_group_id    = module.ecs_service["invoice-service"].security_group_id
  availability_zone    = "${var.aws_region}a"
  s3_temp_bucket       = module.s3_etl_processed.bucket_name

  depends_on = [module.kms, module.aurora_invoice_db, module.s3_etl_raw, module.s3_etl_processed]
}

module "glue_carrier_performance_etl" {
  source = "../../modules/glue-job"

  job_name             = "carrier-performance-etl"
  environment          = local.env
  script_s3_location   = "s3://${module.s3_etl_raw.bucket_name}/glue-scripts/carrier_performance_etl.py"
  kms_key_arn          = module.kms.key_arn
  aurora_connection_string = "jdbc:postgresql://${module.aurora_shipment_db.cluster_endpoint}:5432/shipment_db"
  aurora_username      = var.aurora_glue_username
  aurora_password      = var.aurora_glue_password
  subnet_id            = module.vpc.private_subnet_ids[0]
  security_group_id    = module.ecs_service["shipment-service"].security_group_id
  availability_zone    = "${var.aws_region}a"
  s3_temp_bucket       = module.s3_etl_processed.bucket_name

  depends_on = [module.kms, module.aurora_shipment_db, module.s3_etl_raw, module.s3_etl_processed]
}

# ============================================================
# CloudWatch Monitoring
# ============================================================
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  service_name    = "smartfreight"
  environment     = local.env
  ecs_cluster_name = module.ecs_cluster.cluster_name
  alb_arn_suffix  = module.alb.alb_arn_suffix
  alarm_sns_topic_arn = module.sns_alerts.topic_arn

  ecs_service_names = [
    for name, _ in local.microservices : "smartfreight-${local.env}-${name}"
  ]

  log_group_names = [
    for name, _ in local.microservices : "/ecs/smartfreight-${local.env}/${name}"
  ]

  rds_cluster_identifier = module.aurora_shipment_db.cluster_identifier

  sqs_queue_names = [
    module.sqs_notification.queue_name,
    module.sqs_invoice_processing.queue_name,
    module.sqs_analytics.queue_name,
    module.sqs_shipment_inbound.queue_name,
    module.sqs_carrier_inbound.queue_name,
  ]

  log_metric_filters = [
    {
      name             = "shipment-errors"
      log_group_name   = "/ecs/smartfreight-${local.env}/shipment-service"
      filter_pattern   = "[timestamp, requestId, level=ERROR*, ...]"
      metric_name      = "ShipmentServiceErrors"
      metric_namespace = "SmartFreight/${local.env}"
      metric_value     = "1"
    },
    {
      name             = "invoice-errors"
      log_group_name   = "/ecs/smartfreight-${local.env}/invoice-service"
      filter_pattern   = "[timestamp, requestId, level=ERROR*, ...]"
      metric_name      = "InvoiceServiceErrors"
      metric_namespace = "SmartFreight/${local.env}"
      metric_value     = "1"
    }
  ]

  depends_on = [
    module.ecs_cluster,
    module.ecs_service,
    module.alb,
    module.aurora_shipment_db,
    module.sns_alerts
  ]
}
