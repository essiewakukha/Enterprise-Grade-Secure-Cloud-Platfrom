terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
  # backend "s3" {
  #   bucket = "fintech-tfstate-security-<account_id>"
  #   key    = "02-incident-response/terraform.tfstate"
  #   region = "us-east-1"
  #   dynamodb_table = "tfstate-locks"
  #   encrypt = true
  # }
}

provider "aws" {
  region = var.aws_region
}