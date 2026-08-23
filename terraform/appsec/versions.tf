terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # backend "s3" {
  #   bucket         = "fintech-tfstate-security-207567786898"
  #   key            = "04-appsec/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "tfstate-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::353362989916:role/OrganizationAccountAccessRole"
  }
}