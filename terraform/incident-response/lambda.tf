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
      Principal = {
        Service = "lambda.amazonaws.com"
      }
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
        Sid      = "KMSEncrypt"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = var.findings_kms_key_arn
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
      FINDINGS_BUCKET     = aws_s3_bucket.findings.bucket
      SEVERITY_THRESHOLD  = "7.0"
    }
  }

  kms_key_arn = var.findings_kms_key_arn
}

############################################
# isolate-instance Lambda
############################################

data "archive_file" "isolate_instance" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/isolate-instance"
  output_path = "${path.module}/build/isolate-instance.zip"
}

resource "aws_security_group" "quarantine" {
  name        = "ec2-quarantine-sg"
  description = "No inbound, no outbound. Attached to instances isolated by the incident-response pipeline."
  vpc_id      = var.vpc_id

  # Intentionally no ingress/egress rules -- default deny-all.
  tags = {
    Purpose = "incident-response-isolation"
  }
}

resource "aws_iam_role" "isolate_instance" {
  name = "lambda-isolate-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "isolate_instance" {
  name = "isolate-instance-policy"
  role = aws_iam_role.isolate_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Isolation"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:ModifyInstanceAttribute",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
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

resource "aws_lambda_function" "isolate_instance" {
  function_name    = "isolate-instance"
  role             = aws_iam_role.isolate_instance.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.isolate_instance.output_path
  source_code_hash = data.archive_file.isolate_instance.output_base64sha256

  environment {
    variables = {
      QUARANTINE_SECURITY_GROUP_ID = aws_security_group.quarantine.id
    }
  }
}