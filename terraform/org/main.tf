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