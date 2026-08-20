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
  #   key    = "03-compliance/terraform.tfstate"
  #   region = "af-south-1"
  #   dynamodb_table = "tfstate-locks"
  #   encrypt = true
  # }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "af-south-1"
}

variable "config_bucket_name" {
  description = "S3 bucket receiving AWS Config configuration snapshots/history."
  type        = string
}

variable "sns_topic_arn" {
  description = "Shared security-alerts SNS topic ARN from the 02-incident-response layer."
  type        = string
}