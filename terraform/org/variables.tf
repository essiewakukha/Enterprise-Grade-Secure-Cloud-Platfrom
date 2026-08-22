variable "aws_region" {
  description = "Region for org-layer resources."
  type        = string
  default     = "us-east-1"
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