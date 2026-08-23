############################################
# validate-finding Lambda
############################################

data "archive_file" "validate_finding" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/validate-finding"
  output_path = "${path.module}/build/validate-finding.zip"
}

resource "aws_iam_role" "validate_finding" {
  name = "lambda-validate-finding-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "validate_finding" {
  name = "validate-finding-policy"
  role = aws_iam_role.validate_finding.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3WriteFindings"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.findings.arn}/*"
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "validate_finding" {
  function_name    = "validate-finding"
  role             = aws_iam_role.validate_finding.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.validate_finding.output_path
  source_code_hash = data.archive_file.validate_finding.output_base64sha256

  environment {
    variables = {
      FINDINGS_BUCKET    = aws_s3_bucket.findings.bucket
      SEVERITY_THRESHOLD = "7.0"
    }
  }
}