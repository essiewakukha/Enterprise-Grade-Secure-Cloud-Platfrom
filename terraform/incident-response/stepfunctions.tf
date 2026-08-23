############################################
# IAM role for the Step Functions state machine
############################################

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
        Sid    = "InvokeLambdas"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
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
      }
    ]
  })
}

############################################
# The state machine itself
############################################

resource "aws_sfn_state_machine" "incident_response" {
  name     = "guardduty-incident-response"
  role_arn = aws_iam_role.step_functions.arn

  definition = templatefile("${path.module}/statemachine/incident-response.asl.json", {
    validate_finding_lambda_arn = aws_lambda_function.validate_finding.arn
    isolate_instance_lambda_arn = aws_lambda_function.isolate_instance.arn
    sns_topic_arn                = aws_sns_topic.security_alerts.arn
  })
}