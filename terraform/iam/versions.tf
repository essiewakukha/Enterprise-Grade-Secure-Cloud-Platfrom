terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # backend "s3" {
  #   bucket = "fintech-tfstate-security-<account_id>"
  #   key    = "01-iam/terraform.tfstate"
  #   region = "us-east-1"
  #   dynamodb_table = "tfstate-locks"
  #   encrypt = true
  # }
}

# Apply this layer once per account that needs the DevOpsEngineer role + OIDC
# provider (typically Production and Development). Pass -var-file per account.
provider "aws" {
  region = var.aws_region
}