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
  #   key    = "04-appsec/terraform.tfstate"
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

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "acm_certificate_arn" {
  description = "ACM cert ARN from 05-encryption layer."
  type        = string
}

variable "ami_id" {
  description = "AMI for the sample web app instance (Amazon Linux 2023 recommended)."
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "kms_key_arn" {
  type = string
}