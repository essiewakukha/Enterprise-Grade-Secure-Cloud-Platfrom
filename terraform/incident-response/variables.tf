variable "aws_region" {
  type    = string
  default = "af-south-1"
}

variable "security_alerts_email" {
  description = "Email address subscribed to the SNS topic for security team notification."
  type        = string
}

variable "findings_kms_key_arn" {
  description = "CMK ARN (from 05-encryption layer) used to encrypt the findings S3 bucket, SNS topic, and Lambda environment variables."
  type        = string
}

variable "environment" {
  type    = string
  default = "production"
}

variable "vpc_id" {
  description = "VPC ID where production EC2 workloads and the quarantine SG live."
  type        = string
}