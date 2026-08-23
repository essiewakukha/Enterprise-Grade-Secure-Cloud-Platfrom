resource "aws_cloudwatch_event_rule" "guardduty_high_severity" {
  name        = "guardduty-high-severity-findings"
  description = "Routes GuardDuty findings with severity >= 7.0 (High/Critical) to the incident response state machine."

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
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