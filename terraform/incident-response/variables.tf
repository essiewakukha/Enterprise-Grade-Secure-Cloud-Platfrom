variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "security_alerts_email" {
  description = "Email address subscribed to the SNS topic for security team notifications."
  type        = string
}

variable "environment" {
  type    = string
  default = "production"
}