variable "aws_region" {
  description = "Home region for management/org resources. af-south-1 (Cape Town) is the nearest AWS region to Kenya; consider data-residency requirements from the Central Bank of Kenya's Data Protection guidance before choosing eu-west-1 vs af-south-1."
  type        = string
  default     = "us-east-1"
}

variable "centralized_trail_bucket_name" {
  description = "S3 bucket in the Logging account that receives org-wide CloudTrail logs. Must exist with a bucket policy granting cloudtrail.amazonaws.com PutObject before this trail is created."
  type        = string
}

variable "centralized_trail_kms_key_arn" {
  description = "ARN of the Customer Managed KMS key (in the Logging account) used to encrypt CloudTrail log files."
  type        = string
}

variable "org_account_emails" {
  description = "Root email addresses for each member account AWS Organizations will create."
  type = object({
    security    = string
    logging     = string
    production  = string
    development = string
  })
}

variable "org_account_names" {
  type = object({
    security    = string
    logging     = string
    production  = string
    development = string
  })
  default = {
    security    = "fintech-security"
    logging     = "fintech-logging"
    production  = "fintech-production"
    development = "fintech-development"
  }
}