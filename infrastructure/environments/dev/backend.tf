terraform {
  backend "s3" {
    bucket         = "smartfreight-terraform-state-dev"
    key            = "environments/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "smartfreight-terraform-locks-dev"
    encrypt        = true
  }
}
