output "org_id" {
  value = data.aws_organizations_organization.this.id
}

output "root_ou_id" {
  value = data.aws_organizations_organization.this.roots[0].id
}

output "security_ou_id" {
  value = aws_organizations_organizational_unit.security.id
}

output "production_ou_id" {
  value = aws_organizations_organizational_unit.production.id
}

output "development_ou_id" {
  value = aws_organizations_organizational_unit.development.id
}
output "scp_policy_id" {
  value = aws_organizations_policy.prod_guardrails.id
}
output "logging_account_id" {
  value = aws_organizations_account.logging.id
}
output "security_tooling_account_id" {
  value = aws_organizations_account.security_tooling.id
}

output "production_account_id" {
  value = aws_organizations_account.production.id
}

output "development_account_id" {
  value = aws_organizations_account.development.id
}
output "cloudtrail_arn" {
  value = aws_cloudtrail.org_trail.arn
}

output "cloudtrail_bucket_name" {
  value = aws_s3_bucket.cloudtrail.id
}