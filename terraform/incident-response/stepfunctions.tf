resource "aws_iam_role" "step_functions" {
  name = "incident-response-state-machine-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "step_functions" {
  name = "incident-response-state-machine-policy"
  role = aws_iam_role.step_functions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeLambdas"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.validate_finding.arn,
          aws_lambda_function.isolate_instance.arn
        ]
      },
      {
        Sid      = "PublishSNS"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.security_alerts.arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
                     "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy",
                     "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "state_machine" {
  name              = "/aws/vendedlogs/states/incident-response"
  retention_in_days = 400
}

resource "aws_sfn_state_machine" "incident_response" {
  name     = "guardduty-incident-response"
  role_arn = aws_iam_role.step_functions.arn

  definition = templatefile("${path.module}/statemachine/incident-response.asl.json", {
    validate_finding_lambda_arn = aws_lambda_function.validate_finding.arn
    isolate_instance_lambda_arn = aws_lambda_function.isolate_instance.arn
    sns_topic_arn                = aws_sns_topic.security_alerts.arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.state_machine.arn}:*"
    include_execution_data = true
    level                   = "ALL"
  }

  tracing_configuration {
    enabled = true
  }
}

############################################
# EventBridge: GuardDuty High-severity finding -> Step Functions
############################################

resource "aws_cloudwatch_event_rule" "guardduty_high_severity" {
  name        = "guardduty-high-severity-findings"
  description = "Routes GuardDuty findings with severity >= 7.0 (High/Critical) to the incident response state machine."

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}

resource "aws_iam_role" "eventbridge_sfn_invoke" {
  name = "eventbridge-invoke-state-machine-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_sfn_invoke" {
  name = "eventbridge-invoke-state-machine-policy"
  role = aws_iam_role.eventbridge_sfn_invoke.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = aws_sfn_state_machine.incident_response.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "state_machine" {
  rule     = aws_cloudwatch_event_rule.guardduty_high_severity.name
  arn      = aws_sfn_state_machine.incident_response.arn
  role_arn = aws_iam_role.eventbridge_sfn_invoke.arn
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.incident_response.arn
}

output "findings_bucket_name" {
  value = aws_s3_bucket.findings.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.security_alerts.arn
}