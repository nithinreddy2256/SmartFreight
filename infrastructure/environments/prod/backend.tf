terraform {
  backend "s3" {
    bucket         = "smartfreight-terraform-state-prod"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "smartfreight-terraform-locks-prod"
    encrypt        = true
  }
}
