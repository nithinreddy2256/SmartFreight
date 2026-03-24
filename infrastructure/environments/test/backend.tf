terraform {
  backend "s3" {
    bucket         = "smartfreight-terraform-state-test"
    key            = "environments/test/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "smartfreight-terraform-locks-test"
    encrypt        = true
  }
}
