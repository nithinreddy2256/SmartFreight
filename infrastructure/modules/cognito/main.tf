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

  full_pool_name = "smartfreight-${var.environment}-${var.user_pool_name}"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name = local.full_pool_name

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = var.password_minimum_length
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  mfa_configuration = var.mfa_configuration

  dynamic "software_token_mfa_configuration" {
    for_each = var.mfa_configuration != "OFF" ? [1] : []
    content {
      enabled = true
    }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 3
      max_length = 254
    }
  }

  schema {
    attribute_data_type = "String"
    name                = "given_name"
    required            = false
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 100
    }
  }

  schema {
    attribute_data_type = "String"
    name                = "family_name"
    required            = false
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 100
    }
  }

  user_pool_add_ons {
    advanced_security_mode = var.environment == "prod" ? "ENFORCED" : "AUDIT"
  }

  tags = merge(local.common_tags, {
    Name = local.full_pool_name
  })
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.domain_prefix}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# M2M Resource Server
resource "aws_cognito_resource_server" "m2m" {
  identifier   = var.resource_server_identifier
  name         = "smartfreight-${var.environment}-api"
  user_pool_id = aws_cognito_user_pool.this.id

  dynamic "scope" {
    for_each = var.resource_server_scopes
    content {
      scope_name        = scope.value.scope_name
      scope_description = scope.value.scope_description
    }
  }
}

# App Client for Web/Mobile users
resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.full_pool_name}-web-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = [
    "openid",
    "email",
    "profile"
  ]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  prevent_user_existence_errors = "ENABLED"
}

# App Client for M2M service-to-service auth
resource "aws_cognito_user_pool_client" "m2m" {
  name         = "${local.full_pool_name}-m2m-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = true

  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = [
    for scope in var.resource_server_scopes :
    "${var.resource_server_identifier}/${scope.scope_name}"
  ]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = []

  token_validity_units {
    access_token = "hours"
  }

  access_token_validity = 1

  depends_on = [aws_cognito_resource_server.m2m]
}
