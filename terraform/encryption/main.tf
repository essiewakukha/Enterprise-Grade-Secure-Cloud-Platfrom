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
  #   key    = "05-encryption/terraform.tfstate"
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

variable "domain_name" {
  description = "Public domain name to secure with ACM + HTTPS on the ALB, e.g. app.fintechco.co.ke"
  type        = string
}

data "aws_caller_identity" "current" {}

############################################
# Customer Managed KMS Key
############################################

data "aws_iam_policy_document" "cmk" {
  statement {
    sid       = "EnableRootAccountFullAccess"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid    = "AllowServicesToUseKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type = "Service"
      identifiers = [
        "s3.amazonaws.com",
        "logs.amazonaws.com",
        "sns.amazonaws.com",
        "lambda.amazonaws.com",
        "cloudtrail.amazonaws.com",
        "secretsmanager.amazonaws.com",
      ]
    }
  }
}

resource "aws_kms_key" "cmk" {
  description             = "Fintech platform CMK - encrypts S3, CloudTrail logs, SNS, Lambda env vars, Secrets Manager"
  deletion_window_in_days = 30
  enable_key_rotation     = true # automatic annual rotation
  policy                  = data.aws_iam_policy_document.cmk.json
}

resource "aws_kms_alias" "cmk" {
  name          = "alias/fintech-platform-cmk"
  target_key_id = aws_kms_key.cmk.key_id
}

############################################
# ACM public certificate for the ALB
############################################

resource "aws_acm_certificate" "alb" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation record(s) -- apply these in your public hosted zone
# (Route 53 or external DNS provider) to complete validation:
output "acm_domain_validation_options" {
  value = aws_acm_certificate.alb.domain_validation_options
}

output "cmk_arn" {
  value = aws_kms_key.cmk.arn
}

output "cmk_key_id" {
  value = aws_kms_key.cmk.key_id
}

output "acm_certificate_arn" {
  value = aws_acm_certificate.alb.arn
}