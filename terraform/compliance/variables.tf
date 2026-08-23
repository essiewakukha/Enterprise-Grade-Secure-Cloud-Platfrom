variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "config_bucket_name" {
  description = "S3 bucket that will receive AWS Config configuration snapshots and history. Must not already exist -- we create it in this layer."
  type        = string
}

variable "sns_topic_arn" {
  description = "The security-team-alerts SNS topic ARN from 02-incident-response, reused here for Security Hub findings."
  type        = string
}