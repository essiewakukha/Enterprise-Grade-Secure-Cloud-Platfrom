resource "aws_securityhub_account" "this" {
  enable_default_standards = false
}

resource "aws_securityhub_standards_subscription" "foundational" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# Security Hub auto-ingests findings from GuardDuty, Inspector, and Config
# once they're enabled in the same account/region -- no separate "product
# integration" resource is required for these AWS-native services.
resource "aws_inspector2_enabler" "this" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2", "ECR"]
}

data "aws_caller_identity" "current" {}

############################################
# EventBridge: forward High/Critical Security Hub findings to SNS
############################################

resource "aws_cloudwatch_event_rule" "securityhub_high_severity" {
  name        = "securityhub-high-severity-findings"
  description = "Forwards Security Hub findings with label HIGH or CRITICAL to the security SNS topic."

  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
        RecordState = ["ACTIVE"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "securityhub_to_sns" {
  rule      = aws_cloudwatch_event_rule.securityhub_high_severity.name
  arn       = var.sns_topic_arn
  target_id = "security-hub-findings-to-sns"

  input_transformer {
    input_paths = {
      title    = "$.detail.findings[0].Title"
      severity = "$.detail.findings[0].Severity.Label"
      resource = "$.detail.findings[0].Resources[0].Id"
    }
    input_template = "\"Security Hub Finding [<severity>]: <title> on resource <resource>\""
  }
}

output "securityhub_arn" {
  value = aws_securityhub_account.this.arn
}