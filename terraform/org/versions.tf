terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Recommended: remote state in the Logging/Security account, one state file per layer.
  # backend "s3" {
  #   bucket         = "fintech-tfstate-security-<account_id>"
  #   key            = "00-org/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "tfstate-locks"
  #   encrypt        = true
  # }
}

# This layer must be applied from the Management (root) account of AWS Organizations.
provider "aws" {
  region = var.aws_region
}

# Assumes the auto-created OrganizationAccountAccessRole to operate inside
# the Logging account (077489419337). Everything using provider = aws.logging
# below actually gets created THERE, not in the Management account.
provider "aws" {
  alias  = "logging"
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::077489419337:role/OrganizationAccountAccessRole"
  }
}