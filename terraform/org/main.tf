data "aws_organizations_organization" "this" {}

############################################
# Organizational Units: Security / Production / Development
############################################

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "development" {
  name      = "Development"
  parent_id = data.aws_organizations_organization.this.roots[0].id
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
# Member account: Logging (created first, to validate the pattern)
############################################
# NOTE: this creates a REAL AWS account. Verify org_account_emails.logging
# in terraform.tfvars is correct before applying -- account creation is not
# cleanly reversible (see conversation notes: 90-day close process, email
# gets tied up).

resource "aws_organizations_account" "logging" {
  name      = var.org_account_names.logging
  email     = var.org_account_emails.logging
  parent_id = aws_organizations_organizational_unit.security.id

  lifecycle {
    ignore_changes = [role_name]
  }
}

############################################
# Remaining member accounts: Security tooling, Production, Development
############################################

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
# Organization-wide CloudTrail
############################################

resource "aws_cloudtrail" "org_trail" {
  name                          = "org-management-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_organization_trail         = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  include_global_service_events = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_kms_key.cloudtrail,
  ]
}