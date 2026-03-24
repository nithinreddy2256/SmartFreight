terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

  use_kms         = var.kms_key_arn != ""
  master_username = "smartfreight_admin"
  secret_name     = "smartfreight/${var.environment}/${var.cluster_identifier}/master-credentials"
}

# DB Subnet Group
resource "aws_db_subnet_group" "this" {
  name        = "${var.cluster_identifier}-subnet-group"
  description = "Subnet group for Aurora cluster ${var.cluster_identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.cluster_identifier}-subnet-group"
  })
}

# Security Group for Aurora
resource "aws_security_group" "aurora" {
  name        = "${var.cluster_identifier}-sg"
  description = "Security group for Aurora cluster ${var.cluster_identifier}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "PostgreSQL from allowed security group"
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
    Name = "${var.cluster_identifier}-sg"
  })
}

# Secrets Manager Secret for master credentials
resource "aws_secretsmanager_secret" "master_credentials" {
  name                    = local.secret_name
  description             = "Master credentials for Aurora cluster ${var.cluster_identifier}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0
  kms_key_id              = local.use_kms ? var.kms_key_arn : null

  tags = merge(local.common_tags, {
    Name = local.secret_name
  })
}

# Generate random password
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|;:,.<>?"
}

resource "aws_secretsmanager_secret_version" "master_credentials" {
  secret_id = aws_secretsmanager_secret.master_credentials.id
  secret_string = jsonencode({
    username = local.master_username
    password = random_password.master.result
    engine   = "aurora-postgresql"
    host     = aws_rds_cluster.this.endpoint
    port     = 5432
    dbname   = var.database_name
  })
}

# RDS Parameter Group for Aurora PostgreSQL
resource "aws_rds_cluster_parameter_group" "this" {
  family      = "aurora-postgresql15"
  name        = "${var.cluster_identifier}-pg"
  description = "Parameter group for ${var.cluster_identifier}"

  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_statement"
    value = var.environment == "prod" ? "ddl" : "all"
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_identifier}-pg"
  })
}

# Aurora Cluster
resource "aws_rds_cluster" "this" {
  cluster_identifier               = var.cluster_identifier
  engine                           = "aurora-postgresql"
  engine_version                   = "15.4"
  database_name                    = var.database_name
  master_username                  = local.master_username
  master_password                  = random_password.master.result
  db_subnet_group_name             = aws_db_subnet_group.this.name
  vpc_security_group_ids           = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name  = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = local.use_kms ? var.kms_key_arn : null

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.cluster_identifier}-final-snapshot" : null

  enabled_cloudwatch_logs_exports = ["postgresql"]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverless ? [1] : []
    content {
      max_capacity = var.max_acu
      min_capacity = var.min_acu
    }
  }

  tags = merge(local.common_tags, {
    Name = var.cluster_identifier
  })

  lifecycle {
    ignore_changes = [master_password]
  }
}

# Aurora Instances
resource "aws_rds_cluster_instance" "this" {
  count = var.serverless ? 1 : var.instance_count

  identifier         = "${var.cluster_identifier}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.serverless ? "db.serverless" : var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  tags = merge(local.common_tags, {
    Name = "${var.cluster_identifier}-instance-${count.index + 1}"
  })
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${var.cluster_identifier}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_identifier}-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Secrets Manager rotation
resource "aws_secretsmanager_secret_rotation" "master_credentials" {
  secret_id           = aws_secretsmanager_secret.master_credentials.id
  rotation_lambda_arn = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:SecretsManagerRDSPostgreSQLRotationSingleUser"

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [aws_secretsmanager_secret_version.master_credentials]
}
