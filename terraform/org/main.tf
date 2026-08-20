############################################
# AWS Organizations - Root -> Security OU / Production OU / Development OU
############################################

resource "aws_organizations_organization" "this" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com",
    "ram.amazonaws.com",
  ]
  feature_set = "ALL" # Enables SCPs, tag policies, backup policies, etc.
}

# --- Organizational Units ---

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "development" {
  name      = "Development"
  parent_id = aws_organizations_organization.this.roots[0].id
}

# --- Member accounts ---
# NOTE: aws_organizations_account creates a REAL AWS account. Terraform cannot
# fully destroy accounts (AWS only closes them), so double-check emails/names
# before apply. Each email must be unique and not already used by any AWS account.

resource "aws_organizations_account" "logging" {
  name      = var.org_account_names.logging
  email     = var.org_account_emails.logging
  parent_id = aws_organizations_organizational_unit.security.id

  # Logging account lives under the Security OU alongside the dedicated
  # security-tooling account; it is the CloudTrail/Config delivery target.
  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "security_tooling" {
  name      = var.org_account_names.security
  email     = var.org_account_emails.security
  parent_id = aws_organizations_organizational_unit.security.id

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "production" {
  name      = var.org_account_names.production
  email     = var.org_account_emails.production
  parent_id = aws_organizations_organizational_unit.production.id

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "development" {
  name      = var.org_account_names.development
  email     = var.org_account_emails.development
  parent_id = aws_organizations_organizational_unit.development.id

  lifecycle {
    ignore_changes = [role_name]
  }
}

############################################
# Service Control Policy - Production OU guardrails
############################################

resource "aws_organizations_policy" "prod_guardrails" {
  name        = "prod-critical-action-guardrails"
  description = "Denies termination of EC2 instances and disabling of CloudTrail logging in Production, regardless of local IAM permissions."
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${path.module}/policies/scp-prod-guardrails.json")
}

resource "aws_organizations_policy_attachment" "prod_guardrails" {
  policy_id = aws_organizations_policy.prod_guardrails.id
  target_id = aws_organizations_organizational_unit.production.id
}

############################################
# Organization-wide CloudTrail -> centralized Logging account bucket
############################################

resource "aws_cloudtrail" "org_trail" {
  name                          = "org-management-trail"
  s3_bucket_name                = var.centralized_trail_bucket_name
  is_organization_trail         = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  include_global_service_events = true
  kms_key_id                    = var.centralized_trail_kms_key_arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_organizations_organization.this]
}